#!/bin/bash

# ==========================================
# --- KONFIGURÁCIA ---
# ==========================================
# Ak tvoje úložisko nepodporuje snapshoty, nastav na "no" pre čisté logy
# Ak ho v budúcnosti zmeníš na ZFS/LVM-Thin, zmeň na "yes"
ENABLE_SNAPSHOTS="yes"
MAX_SNAPSHOTS=5

# ==========================================
# --- FUNKCIE ---
# ==========================================

# Funkcia pre aktívne čakanie na sieť (TCP test na port 53)
wait_for_network() {
    local CTID=$1
    local MAX_RETRIES=12
    local WAIT_TIME=2
    
    echo "⏳ Overujem dostupnosť DNS/Sieťových služieb pre $CTID (bez ping)..."
    for ((i=1; i<=MAX_RETRIES; i++)); do
        if pct exec $CTID -- bash -c "timeout 1 bash -c '</dev/tcp/1.1.1.1/53' 2>/dev/null"; then
            echo "🌐 Sieťová konektivita potvrdená."
            return 0
        fi
        sleep $WAIT_TIME
    done
    
    echo "⚠️ Varovanie: Sieť v $CTID sa nezdá byť plne pripravená."
    return 1
}

# Funkcia pre vytvorenie a rotáciu snapshotov
rotate_snapshots() {
    local CTID=$1
    
    # Inovácia: Ak sú snapshoty vypnuté v konfigurácii, funkciu ticho ukončíme
    if [ "$ENABLE_SNAPSHOTS" != "yes" ]; then
        return 0
    fi

    local PREFIX="autoupdate"
    local TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    local NEW_SNAP="${PREFIX}_${TIMESTAMP}"
    
    echo "🔍 Pokus o snapshot pre LXC $CTID..."
    
    if pct snapshot $CTID "$NEW_SNAP" --description "Auto-záloha $TIMESTAMP" 2>/dev/null; then
        echo "✅ Snapshot $NEW_SNAP vytvorený."
        
        local SNAPS=$(pct listsnapshot $CTID | grep "$PREFIX" | awk '{print $1}')
        local COUNT=$(echo "$SNAPS" | wc -l)

        if [ "$COUNT" -gt "$MAX_SNAPSHOTS" ]; then
            local TO_DELETE_COUNT=$((COUNT - MAX_SNAPSHOTS))
            local TO_DELETE=$(echo "$SNAPS" | head -n $TO_DELETE_COUNT)
            for OLD_SNAP in $TO_DELETE; do
                echo "🗑️ Mažem starý snapshot: $OLD_SNAP"
                pct delsnapshot $CTID "$OLD_SNAP" 2>/dev/null
            done
        fi
    else
        echo "⚠️ Úložisko LXC $CTID nepodporuje snapshoty. Pokračujem bez nich."
    fi
}

# ==========================================
# --- HLAVNÝ PROGRAM ---
# ==========================================

# Získanie zoznamu všetkých ID kontajnerov
CTIDS=$(pct list | awk 'NR>1 {print $1}')

for CTID in $CTIDS; do
    STATUS=$(pct status $CTID | awk '{print $2}')
    OS_TYPE=$(pct config $CTID | grep "ostype" | awk '{print $2}')

    # Kontrola, či ide o Debian/Ubuntu
    if [[ "$OS_TYPE" == "debian" || "$OS_TYPE" == "ubuntu" ]]; then
        echo "🔄 Spracovávam LXC $CTID ($STATUS)..."

        WAS_STOPPED=false

        # Zapnutie, ak je vypnutý
        if [ "$STATUS" == "stopped" ]; then
            echo "🚀 Zapínam kontajner $CTID..."
            pct start $CTID
            WAS_STOPPED=true
        fi

        # Overenie siete
        wait_for_network $CTID || {
            echo "❌ Preskakujem aktualizáciu pre $CTID pre nedostupnosť siete."
            [ "$WAS_STOPPED" == true ] && pct shutdown $CTID
            echo "---------------------------------------"
            continue
        }

        # Snapshot logika
        rotate_snapshots $CTID

        echo "📦 Aktualizujem LXC $CTID..."
        pct exec $CTID -- bash -c "export DEBIAN_FRONTEND=noninteractive; \
            apt-get update -y && \
            apt-get dist-upgrade -y -o Dpkg::Options::=\"--force-confdef\" -o Dpkg::Options::=\"--force-confold\" && \
            apt-get autoremove -y && \
            apt-get clean"

        if [ $? -eq 0 ]; then
            echo "✅ LXC $CTID aktualizácia prebehla úspešne."
        else
            echo "❌ LXC $CTID narazil na chybu počas aktualizácie."
        fi

        # Návrat do pôvodného stavu
        if [ "$WAS_STOPPED" == true ]; then
            echo "🔌 Vypínam kontajner $CTID..."
            pct shutdown $CTID
            sleep 2 
        fi
        
        echo "---------------------------------------"
    else
        echo "⏭️ LXC $CTID preskočený (nepodporovaný OS: $OS_TYPE)."
        echo "---------------------------------------"
    fi
done

echo "🎉 Všetky LXC kontajnery boli spracované."
