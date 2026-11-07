# 📅 Guia Definitivo de Sincronização com o Google Calendar

Este guia explica detalhadamente as **duas formas** de conectar sua conta do Google Calendar ao plugin do Omarchy, as diferenças entre elas e o passo a passo completo.

---

## ⚖️ Comparativo entre os Métodos

| Recurso | Opção 1: Link iCal Secreto (.ics) | Opção 2: Google Cloud OAuth2 |
|---|---|---|
| **Tempo de Configuração** | ⚡ **30 segundos** | 🛠️ **3 a 5 minutos** (única vez) |
| **Direção da Sincronização** | 📥 **Unidirecional** (Google ➔ Omarchy) | 🔄 **Bidirecional** (Google ⇄ Omarchy) |
| **Criação de Eventos** | Salva localmente no Omarchy | Envia direto para a nuvem / celular |
| **Google Cloud / Dev** | ❌ **Nenhum** | ✅ Projeto gratuito no Google Cloud |
| **Expiração** | 🔒 Permanente (link privado) | 🔄 Tokens com renovação automática |
| **Ideal Para** | Quem só quer ver a agenda e alertas | Controle total (adicionar/editar reuniões) |

---

## ⚡ Opção 1: Link iCal Secreto (Rápido — 30 segundos)

Ideal se você só quer visualizar seus compromissos, receber notificações de reuniões e ver a agenda na barra superior.

### Passo a Passo:
1. Abra o [Google Agenda (Web)](https://calendar.google.com/) no seu navegador.
2. Na barra lateral esquerda ("Minhas agendas"), passe o mouse sobre a sua agenda principal e clique nos **três pontinhos (`⋮`) > Configurações e compartilhamento**.
3. Role a página para baixo até a seção **"Integrar agenda"**.
4. Localize o campo **"Endereço secreto em formato iCal"** e clique no botão de copiar (o link tem o formato `https://calendar.google.com/calendar/ical/.../basic.ics`).
   > ⚠️ **Atenção:** Copie o endereço **secreto**, não o público. O endereço secreto permite acessar seus eventos sem torná-los visíveis na internet.
5. No Omarchy, clique no relógio na barra superior para abrir o calendário.
6. Pressione a tecla `S` (ou clique no ícone da engrenagem `󰒓` no topo).
7. Cole o link no campo **"URL iCal (.ics)"** e clique em **"Salvar e Sincronizar"** (ou pressione Enter).

Pronto! Em poucos segundos todos os seus eventos aparecerão organizados nas visões de Dia, Semana, Mês e Ano.

---

## 🔄 Opção 2: Google Cloud OAuth2 (Bidirecional Definitivo)

Ideal se você quer que os eventos criados no Omarchy (pelo botão `+ Evento`, atalho `N` ou comando `omarchy-gcal add`) sejam salvos diretamente na nuvem do Google e sincronizados instantaneamente no seu celular, tablet e navegador.

### Passo 1: Criar um Projeto no Google Cloud (Gratuito)
1. Acesse o [Google Cloud Console](https://console.cloud.google.com/).
2. Faça login com a sua conta do Google.
3. No topo da tela, clique no seletor de projetos e clique em **"Novo projeto"**.
4. Dê um nome ao projeto (exemplo: `Omarchy Calendar`) e clique em **"Criar"**.
5. Certifique-se de que o novo projeto está selecionado no topo da página.

### Passo 2: Ativar a API do Google Calendar
1. No menu lateral (ou barra de busca do topo), vá em **"APIs e serviços" > "Biblioteca"**.
2. Digite `Google Calendar API` na busca.
3. Clique em **Google Calendar API** e depois no botão azul **"Ativar"** (Enable).

### Passo 3: Configurar a Tela de Consentimento OAuth
1. No menu lateral esquerdo, clique em **"Tela de permissão OAuth"** (OAuth consent screen).
2. Selecione o tipo de usuário: **"Externo"** (External) e clique em **"Criar"**.
3. Preencha as informações básicas obrigatórias:
   - **Nome do app:** `Omarchy Calendar`
   - **E-mail para suporte:** seu próprio e-mail do Google.
   - **Dados de contato do desenvolvedor:** seu próprio e-mail.
4. Clique em **"Salvar e continuar"**.
5. Na etapa **"Escopos"** (Scopes), clique em **"Adicionar ou remover escopos"**, procure por `.../auth/calendar` (Google Calendar API), selecione e confirme. Clique em **"Salvar e continuar"**.
6. Na etapa **"Usuários de teste"** (Test users), clique em **"+ Add users"**, insira o seu e-mail do Google e confirme. (Isso permite que você faça login com sua conta mesmo sem publicar o app publicamente).
7. Clique em **"Salvar e continuar"**.

### Passo 4: Criar as Credenciais (OAuth Client ID)
1. No menu lateral esquerdo, clique em **"Credenciais"** (Credentials).
2. Clique em **"+ Criar credenciais" > "ID do cliente OAuth"**.
3. Em **Tipo de aplicativo**, selecione **"App para computador"** (Desktop app).
4. Em **Nome**, coloque `Omarchy Shell` e clique em **"Criar"**.
5. Uma janela com o seu cliente criado será exibida. Clique no botão **"Fazer o download do JSON"** (ícone de seta para baixo ⬇️).

### Passo 5: Conectar ao Omarchy
Abra o seu terminal e execute:

```bash
omarchy-gcal auth --credentials-file ~/Downloads/client_secret_*.json
```
*(Substitua o caminho pelo nome do arquivo baixado na sua pasta Downloads)*.

> **Dica Alternativa via Interface Gráfica:**  
> Se preferir, renomeie o arquivo baixado para `credentials.json` e mova-o para `~/.config/omarchy/gcal/credentials.json`:
> ```bash
> mkdir -p ~/.config/omarchy/gcal
> cp ~/Downloads/client_secret_*.json ~/.config/omarchy/gcal/credentials.json
> ```
> Depois abra o calendário, pressione `S` e clique no botão **"Conectar via OAuth2"**.

### Passo 6: Autorizar no Navegador
1. O comando abrirá automaticamente uma aba no seu navegador.
2. Selecione sua conta do Google.
3. Caso veja a tela *"O Google não verificou este app"*, clique em **"Avançado" > "Acessar Omarchy Calendar (não seguro)"** (isto é normal, pois o aplicativo foi criado por você em modo de teste pessoal).
4. Marque a caixa de permissão para ver e gerenciar sua agenda e clique em **"Continuar"**.
5. O navegador exibirá a mensagem de sucesso: *"Google Calendar conectado ao Omarchy!"*.

Pronto! Sua agenda está conectada de forma definitiva. O Omarchy renovará seus tokens automaticamente em segundo plano.

---

## 🛠️ Comandos Úteis do Terminal

```bash
# Verificar status da conexão e calendário sincronizado
omarchy-gcal status

# Forçar sincronização imediata
omarchy-gcal sync

# Listar próximos eventos
omarchy-gcal list --upcoming

# Buscar eventos por palavra-chave
omarchy-gcal list -q "Reunião"

# Adicionar um evento direto pelo terminal (com OAuth2, sincroniza na nuvem)
omarchy-gcal add --title "Reunião de Equipe" --date 2026-11-10 --start 14:00 --end 15:00 --location "Google Meet"
```
