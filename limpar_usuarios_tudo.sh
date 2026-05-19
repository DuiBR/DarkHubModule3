#!/bin/bash
# Compatível com execução interativa e execução remota pelo painel.
# Use --yes ou AUTO_CONFIRM=s para confirmar automaticamente sem prompt.
if [ -t 1 ] && command -v clear >/dev/null 2>&1; then clear; fi
AUTO_CONFIRM="${AUTO_CONFIRM:-}"
for arg in "$@"; do
  case "$arg" in
    --yes|-y) AUTO_CONFIRM="s" ;;
    --no-restore) AUTO_RESTORE="n" ;;
  esac
done
AUTO_RESTORE="${AUTO_RESTORE:-n}"

RED='\033[1;31m'
GREEN='\033[1;32m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
RESET='\033[0m'

fun_prog() {
  local comando="$1"
  # usa eval para interpretar loops e redirecionamentos corretamente
  eval "$comando" > /dev/null 2>&1 &
  pid=$!
  if [ -t 1 ] && command -v tput >/dev/null 2>&1; then tput civis; fi
  echo -ne "\033[1;32m.\033[1;33m.\033[1;31m. \033[1;32m"
  while kill -0 $pid 2>/dev/null; do
    for i in / - \\ \|; do
      sleep .1
      echo -ne "\e[1D${i}"
    done
  done
  if [ -t 1 ] && command -v tput >/dev/null 2>&1; then tput cnorm; fi
  echo -e "\e[1D\033[1;32mOK\033[0m"
  sleep 1
}

echo -e "\n${RED}⚠️  ATENÇÃO: Este processo irá:${RESET}"
echo -e "${YELLOW}- Apagar todos os usuários criados (exceto root e nobody)"
echo "- Limpar senhas SSHPlus"
echo "- Zerar o arquivo /root/usuarios.db"
echo "- Apagar jobs do at"
echo "- Limpar arquivos de teste"
echo -e "- Remover todos os usuários de V2Ray e Xray (clientes do JSON)${RESET}"
echo

# Detecta o backup mais recente
BACKUP_DIR=$(ls -dt /root/backup_limpeza_* 2>/dev/null | head -n1)

if [[ -n "$BACKUP_DIR" && -d "$BACKUP_DIR" ]]; then
  echo -e "${GREEN}📦 Backup encontrado: ${BACKUP_DIR}${RESET}"
  if [ "$AUTO_CONFIRM" = "s" ]; then
    RESTORE="$AUTO_RESTORE"
    echo -e "${YELLOW}Restauração automática: ${RESTORE}${RESET}"
  else
    read -rp $'\033[1;33mDeseja restaurar este backup? (s/N): \033[0m' RESTORE || RESTORE="n"
  fi
  case "$RESTORE" in
    [sS])
      echo -ne "${CYAN}🔄 Restaurando backup...${RESET} "
      fun_prog "bash -c \"
        cp '$BACKUP_DIR'/passwd /etc/passwd
        cp '$BACKUP_DIR'/shadow /etc/shadow
        cp '$BACKUP_DIR'/group /etc/group
        cp '$BACKUP_DIR'/gshadow /etc/gshadow
        [ -f '$BACKUP_DIR'/usuarios.db ] && cp '$BACKUP_DIR'/usuarios.db /root/usuarios.db
        [ -d '$BACKUP_DIR'/senha ] && cp -r '$BACKUP_DIR'/senha /etc/SSHPlus/
        [ -f '$BACKUP_DIR'/v2ray_config.json ] && cp '$BACKUP_DIR'/v2ray_config.json /etc/v2ray/config.json
        [ -f '$BACKUP_DIR'/xray_config.json ] && cp '$BACKUP_DIR'/xray_config.json /usr/local/etc/xray/config.json
        [ -d '$BACKUP_DIR'/TesteAtlas ] && cp -r '$BACKUP_DIR'/TesteAtlas /etc/
        [ -d '$BACKUP_DIR'/atlasteste ] && cp -r '$BACKUP_DIR'/atlasteste /root/atlasteste
      \""
      echo -e "${GREEN}✓ Backup restaurado com sucesso.${RESET}"
      exit 0
      ;;
    *)
      # remove todos os backups antigos
      for d in /root/backup_limpeza_*; do
        [[ "$d" != "$BACKUP_DIR" ]] && rm -rf "$d"
      done
      ;;
  esac
fi

if [ "$AUTO_CONFIRM" = "s" ]; then
  confirm="s"
  echo -e "${YELLOW}Confirmação automática recebida (--yes/AUTO_CONFIRM=s).${RESET}"
else
  read -p $'\033[1;31mDeseja continuar com a limpeza? (s/N): \033[0m' confirm || confirm="n"
fi
if [[ ! "$confirm" =~ ^[sS]$ ]]; then
  echo -e "${CYAN}❌ Operação cancelada.${RESET}"
  exit 1
fi

echo -e "${CYAN}⏳ Iniciando limpeza...${RESET}\n"

# Backup
echo -ne "${CYAN}🔹 Gerando backup de segurança...${RESET} "
fun_prog "bash -c '
  BACKUP_DIR=\"/root/backup_limpeza_$(date +%Y%m%d_%H%M%S)\"
  mkdir -p \"$BACKUP_DIR\"
  cp /etc/passwd /etc/shadow /etc/group /etc/gshadow \"$BACKUP_DIR\"
  [ -f /root/usuarios.db ] && cp /root/usuarios.db \"$BACKUP_DIR\"
  [ -d /etc/SSHPlus/senha ] && cp -r /etc/SSHPlus/senha \"$BACKUP_DIR/senha\"
  [ -f /etc/v2ray/config.json ] && cp /etc/v2ray/config.json \"$BACKUP_DIR/v2ray_config.json\"
  [ -f /usr/local/etc/xray/config.json ] && cp /usr/local/etc/xray/config.json \"$BACKUP_DIR/xray_config.json\"
  [ -d /etc/TesteAtlas ] && cp -r /etc/TesteAtlas \"$BACKUP_DIR/TesteAtlas\"
  [ -d /root/atlasteste ] && cp -r /root/atlasteste \"$BACKUP_DIR/atlasteste\"'"

# Remover usuários
echo -e "${CYAN}🔹 Removendo usuários do sistema!${RESET}"
# prepara lista e contador
awk -F: '$3>=1000 && $1!~/^(root|nobody)$/{print $1}' /etc/passwd > /tmp/removed_list
count=$(wc -l < /tmp/removed_list)
echo -ne "${CYAN}🔹${RESET} ${YELLOW}$count${RESET} ${CYAN}usuários para remover...${RESET} "
# executa a remoção com spinner
fun_prog "bash -c '
  while IFS= read -r u; do
    userdel -r -f \"\$u\"
  done < /tmp/removed_list
'"
echo -e "${CYAN}🔹 Usuários removidos: ${YELLOW}$count${RESET}"
rm -f /tmp/removed_list

# SSHPlus
echo -ne "${CYAN}🔹 Limpando senhas SSHPlus...${RESET} "
fun_prog "bash -c '[ -d /etc/SSHPlus/senha ] && rm -rf /etc/SSHPlus/senha/*'"

# usuarios.db
echo -ne "${CYAN}🔹 Resetando /root/usuarios.db...${RESET} "
fun_prog "bash -c '[ -f /root/usuarios.db ] && > /root/usuarios.db'"

# Pastas de teste
echo -ne "${CYAN}🔹 Limpando pastas de teste...${RESET} "
fun_prog "bash -c '[ -d /etc/TesteAtlas ] && rm -rf /etc/TesteAtlas/*; [ -d /root/atlasteste ] && rm -rf /root/atlasteste/*'"

# Jobs agendados
echo -ne "${CYAN}🔹 Cancelando jobs agendados (at)...${RESET} "
fun_prog "bash -c '
    if command -v atq >/dev/null; then
        atq | awk \"{print \$1}\" | while read job; do
            atrm \"\$job\"
        done
    fi'"

# Limpar V2Ray/Xray
limpar_clients_json() {
    local arquivo=$1
    local tipo=$2
    local total_clientes=0
    if [ -f "$arquivo" ]; then
        if grep -q '"clients"' "$arquivo"; then
            if [ "$tipo" = "v2ray" ]; then
                total_clientes=$(jq '.inbounds[0].settings.clients | length' "$arquivo" 2>/dev/null)
                jq '(.inbounds[0].settings.clients) = []' "$arquivo" > "${arquivo}.tmp" && mv "${arquivo}.tmp" "$arquivo"
            elif [ "$tipo" = "xray" ]; then
                total_clientes=$(jq '[.inbounds[] | select(.tag == "inbound-sshplus") | .settings.clients[]] | length' "$arquivo" 2>/dev/null)
                jq '(.inbounds[] | select(.tag == "inbound-sshplus") | .settings.clients) = []' "$arquivo" > "${arquivo}.tmp" && mv "${arquivo}.tmp" "$arquivo"
            fi
            chmod 644 "$arquivo"
            echo -e "${CYAN}🔹 Clientes removidos do $tipo: ${YELLOW}$total_clientes${RESET}"
        fi
    fi
}

limpar_clients_json "/etc/v2ray/config.json" "v2ray"
limpar_clients_json "/usr/local/etc/xray/config.json" "xray"

# Reiniciar
echo -ne "${CYAN}🔹 Verificando e reiniciando serviços Xray/V2Ray...${RESET} "
fun_prog "bash -c '
    for serv in v2ray xray; do
        if [ -f \"/etc/${serv}/config.json\" ] || [ -f \"/usr/local/etc/${serv}/config.json\" ]; then
            systemctl restart \"$serv\" 2>/dev/null
        fi
    done'"

echo -e "${GREEN}✅ Limpeza completa!${RESET}"
