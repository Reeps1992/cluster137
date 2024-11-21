#!/bin/bash

# Couleurs
RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
BLUE='\e[34m'
ORANGE='\e[38;5;208m'
NC='\e[0m' # No Color

CONFIG_FILE=".config/config.yml"
NODES_CONFIG="nodes.conf"
PARA_SCRIPT="para.sh"
START_PORT=40000
REMOTE_USER="root"

echo ""
echo -e "$BLUE"
echo "                                                                                                                      "
echo "                                               .,                     ,                                               "
echo "                                              ,Wt .    .           f#i j.                      L                     "
echo "            ;                .. GEEEEEEEL    i#D  Di   Dt        .E#t  EW,                     #K:    :;;;;;;;;;;;;;."
echo "          .DL               ;W,    L#K      f#f   E#i  E#i      i#W,   E##j               jt   :K#t    jWWWWWWWW###L "
echo "  f.     :K#L     LWL      j##,    t#E    .D#i    E#t  E#t     L#D.    E###D.             G#t    L#G.          ,W#f  "
echo "  EW:   ;W##L   .E#f      G###,    t#E   :KW,     E#t  E#t   :K#Wfff;  E#jG#W;  .......   E#t     t#W,        ,##f   "
echo "  E#t  t#KE#L  ,W#;     :E####,    t#E   t#f      E########  i##WLLLL  E#t t##f  GEEEEEE  E#t  .jffD##f      i##j    "
echo "  E#t f#D.L#L t#K:     ;W#DG##,    t#E    ;#G     E#j  K#j    .E#L     E#t  :K#E:         E#t  .fLLLD##L    i##t     "
echo "  E#jG#f  L#LL#G      j### W##,    t#E     :KE.   E#t  E#t      f#E:   E#KDDDD###i        E#t     ;W#i     t##t      "
echo "  E###;   L###j      G##i,,G##,    t#E      .DW:  E#t  E#t       ,WW;  E#f,t#Wi,          E#t    j#E.     t##i       "
echo "  E#K:    L#W;     :K#K:   L##,    t#E        L#, f#t  f#         .D#; E#t  ;#W:          E#t  .D#f      j##;        "
echo "  EG      LE.     ;##D.    L##,     fE         t:  ii   ii          tt DWi   ,KK:         tf,  KW,      :##,         "
echo "                                                                                                                      "
echo -e "$BLUE"                                                                                                               
echo "                                                                                                          by Reegz    "
echo -e "$NC"
echo ""       

init_config_files() {
    mkdir -p "$(dirname "$NODES_CONFIG")"
    
    if [ ! -f "$PARA_SCRIPT" ]; then
        echo -e "${ORANGE}Création du script para.sh...$NC"
        cat > "$PARA_SCRIPT" << 'EOL'
#!/bin/bash

DIR_PATH=$(cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P)

os="${1:-linux}"
architecture="${2:-amd64}"
startingCore="${3:-0}"
maxCores="${4:-1}"
version="${5:-latest}"
main_pid=$$
crashed=0

NODE_BINARY="$DIR_PATH/node-$version-$os-$architecture"

if [ ! -f "$NODE_BINARY" ]; then
    echo "Erreur: Binaire non trouvé: $NODE_BINARY"
    exit 1
fi

if [ -z "$maxCores" ] || [ "$maxCores" -lt 1 ]; then
    echo "Erreur: Nombre de cores invalide"
    exit 1
fi

start_process() {
    echo "Arrêt des processus existants..."
    pkill -f "node-$version-$os-$architecture" || true
    
    local parent_pid

    if [ "$startingCore" = 0 ]; then
        echo "Démarrage du processus principal..."
        "$NODE_BINARY" &
        parent_pid=$!
        if [ "$crashed" = 0 ]; then
            maxCores=$((maxCores - 1))
        fi
    else
        parent_pid=$main_pid
    fi

    echo "Node parent ID: $parent_pid"
    echo "Max Cores: $maxCores"
    echo "Starting Core: $startingCore"

    for i in $(seq 1 "$maxCores"); do
        core=$((startingCore + i))
        echo "Deploying: $core data worker with params: --core=$core --parent-process=$parent_pid"
        "$NODE_BINARY" --core="$core" --parent-process="$parent_pid" &
        sleep 0.5
    done
}

is_process_running() {
    if [ "$startingCore" = 0 ]; then
        pgrep -f "node-$version-$os-$architecture$" >/dev/null
    else
        ps -p "$main_pid" >/dev/null 2>&1
    fi
}

cleanup() {
    echo "Arrêt de tous les processus..."
    pkill -P $$ || true
    exit 0
}

trap cleanup INT TERM

start_process

while true; do
    if ! is_process_running; then
        echo "Process crashed or stopped. restarting..."
        crashed=$((crashed + 1))
        start_process
    fi
    sleep 440
done
EOL
        chmod +x "$PARA_SCRIPT"
        echo -e "${GREEN}Script para.sh créé$NC"
    fi
    
    if [ ! -f "$NODES_CONFIG" ]; then
        echo -e "${ORANGE}Création du fichier de configuration template...$NC"
        cat > "$NODES_CONFIG" << EOL
# Format: ip|workers|password|remote_config_file
# Attention !!! Si la ligne est commentée alors l'IP ne sera pas servie par le script. !!!
# exemple: 192.168.1.29|32|1|/home/user/ceremonyclient/node/.config/config.yml
EOL
        chmod 600 "$NODES_CONFIG"
        echo -e "${BLUE}Veuillez remplir le fichier $NODES_CONFIG avec vos valeurs puis relancer le script$NC"
        echo -e "${BLUE}puis lancez la commande ./cluster137.sh --help pour commencer$NC" 
        exit 1
    fi

    if ! grep -v '^#' "$NODES_CONFIG" > /dev/null; then
        echo -e "${RED}Le fichier $NODES_CONFIG ne contient que des commentaires$NC"
        echo -e "${BLUE}Veuillez le remplir avec vos valeurs puis relancer le script$NC"
        exit 1
    fi
}

generate_worker_config() {
    local port=$START_PORT
    echo "engine:"
    echo "  dataWorkerMultiaddrs:"
    
    while IFS='|' read -r line || [ -n "$line" ]; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [ -z "$line" ] && continue
        
        ip=$(echo "$line" | cut -d'|' -f1)
        workers=$(echo "$line" | cut -d'|' -f2)
        
        echo "    # Node ${ip}"
        for ((i=0; i<workers; i++)); do
            echo "    - /ip4/${ip}/tcp/${port}"
            ((port++))
        done
    done < "$NODES_CONFIG"
}

apply_master_config() {
    local backup_file="${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$CONFIG_FILE" "$backup_file"
    echo -e "${BLUE}Backup du config.yml actuel créé: $backup_file$NC"

    temp_file=$(mktemp)
    
    in_worker_section=false
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*dataWorkerMultiaddrs: ]]; then
            generate_worker_config >> "$temp_file"
            in_worker_section=true
        elif [[ "$line" =~ ^[[:space:]]*- ]] && [ "$in_worker_section" = true ]; then
            continue
        else
            in_worker_section=false
            echo "$line" >> "$temp_file"
        fi
    done < "$CONFIG_FILE"

    mv "$temp_file" "$CONFIG_FILE"
    echo -e "${GREEN}Configuration du master mise à jour avec succès$NC"
}

deploy_to_slaves() {
    echo -e "${BLUE}Déploiement de la configuration vers les slaves...$NC"
    SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
    
    local found_master=false
    
    while IFS='|' read -r line || [ -n "$line" ]; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [ -z "$line" ] && continue
        
        ip=$(echo "$line" | cut -d'|' -f1)
        password=$(echo "$line" | cut -d'|' -f3)
        remote_path=$(echo "$line" | cut -d'|' -f4)
        
        if [ "$found_master" = true ]; then
            echo -e "${BLUE}Déploiement vers le slave: $ip$NC"
            if sshpass -p "$password" ssh $SSH_OPTS ${REMOTE_USER}@${ip} "mkdir -p $(dirname $remote_path)" 2>/dev/null && \
               sshpass -p "$password" scp $SSH_OPTS "$CONFIG_FILE" ${REMOTE_USER}@${ip}:${remote_path} 2>/dev/null; then
                echo -e "${GREEN}✓ Configuration déployée avec succès sur $ip$NC"
            else
                echo -e "${RED}✗ Erreur lors du déploiement sur $ip$NC"
            fi
        else
            found_master=true
        fi
    done < "$NODES_CONFIG"
}

show_help() {
    echo -e "${YELLOW}Usage: $0 [--apply] [--deploy] [--start] [--help]"
    echo "Options:"
    echo "  --apply  : Mettre à jour le config.yml du master"
    echo "  --deploy : Déployer le config.yml vers tous les slaves actifs"
    echo "  --start  : Lancer le script para.sh (ne peut être combiné avec d'autres options)"
    echo "  --help   : Afficher cette aide"
    echo ""
    echo "Configuration dans: $NODES_CONFIG"
    echo "Format: ip|workers|password|remote_config_file"
    echo "Note: Le premier nœud non commenté est considéré comme le master"
    echo ""
    echo "Exemples:"
    echo "  $0                     # Affiche la configuration"
    echo "  $0 --apply            # Met à jour le master uniquement"
    echo "  $0 --deploy           # Déploie la config actuelle vers les slaves"
    echo "  $0 --apply --deploy   # Met à jour le master et déploie vers les slaves"
    echo "  $0 --start            # Lance le cluster avec para.sh$NC"
}

init_config_files

APPLY=false
DEPLOY=false
START=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --help)
            show_help
            exit 0
            ;;
        --apply)
            APPLY=true
            shift
            ;;
        --deploy)
            DEPLOY=true
            shift
            ;;
        --start)
            if [ "$APPLY" = true ] || [ "$DEPLOY" = true ]; then
                echo -e "${RED}Erreur: L'option --start ne peut pas être combinée avec d'autres options$NC"
                exit 1
            fi
            START=true
            shift
            ;;
        *)
            echo -e "${RED}Option inconnue: $1$NC"
            show_help
            exit 1
            ;;
    esac
done

if [ "$START" = true ]; then
    startCore=0
    workers=""
    while IFS='|' read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [ -z "$line" ] && continue
        
        current_workers=$(echo "$line" | cut -d'|' -f2)
        if [ -z "$workers" ]; then
            # Premier nœud (master)
            workers="$current_workers"
        else
            # Nœuds suivants
            startCore=$workers
            workers="$current_workers"
            break
        fi
    done < "$NODES_CONFIG"
    
    if [ -z "$workers" ]; then
        echo -e "${RED}Erreur: Impossible de déterminer le nombre de workers$NC"
        exit 1
    fi
    
    echo -e "${BLUE}Lancement du cluster avec startCore=$startCore et workers=$workers$NC"
    "./para.sh" "linux" "amd64" "$startCore" "$workers" "latest"
    exit $?
fi

if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}Erreur: Fichier de configuration non trouvé: $CONFIG_FILE$NC"
    exit 1
fi

if [ "$APPLY" = true ]; then
    apply_master_config
fi

if [ "$DEPLOY" = true ]; then
    deploy_to_slaves
fi

if [ "$APPLY" = false ] && [ "$DEPLOY" = false ] && [ "$START" = false ]; then
    generate_worker_config
fi