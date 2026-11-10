# Guia de sincronização com o Google Calendar

[🇺🇸 English](sync-guide.md) · **🇧🇷 Português (Brasil)**

Este guia explica as **duas formas** de conectar sua conta do Google Calendar ao plugin
Calendar for Google do Omarchy, a diferença entre elas e o passo a passo completo.

Este plugin não é afiliado ao Google. Google Calendar é uma marca do Google LLC.

---

## Comparativo entre os métodos

| Recurso | Opção 1: link iCal secreto (.ics) | Opção 2: OAuth2 do Google Cloud |
|---|---|---|
| **Tempo de configuração** | **30 segundos** | **3 a 5 minutos** (uma única vez) |
| **Direção da sincronização** | **Unidirecional** (Google ➔ Omarchy) | **Bidirecional** (Google ⇄ Omarchy) |
| **Criação de eventos** | Salva localmente no Omarchy | Envia direto para o Google (celular, web) |
| **Google Cloud** | Nenhum | Projeto gratuito no Google Cloud |
| **Expiração** | Permanente (link privado) | Tokens renovados automaticamente |
| **Ideal para** | Ver a agenda e receber lembretes | Controle total (criar, mover, apagar eventos) |

---

## Opção 1: link iCal secreto (rápido, 30 segundos)

Ideal se você só quer ver seus compromissos, receber notificações de reuniões e ver a
agenda na barra.

1. Abra o [Google Agenda (web)](https://calendar.google.com/) no navegador.
2. Na barra lateral esquerda ("Minhas agendas"), passe o mouse sobre a sua agenda
   principal e clique nos **três pontinhos (`⋮`) > Configurações e compartilhamento**.
3. Role a página até a seção **"Integrar agenda"**.
4. Copie o campo **"Endereço secreto em formato iCal"** (o link tem o formato
   `https://calendar.google.com/calendar/ical/.../basic.ics`).
   > **Atenção:** copie o endereço **secreto**, não o público. O endereço secreto dá
   > acesso aos seus eventos sem torná-los públicos na internet. Não o compartilhe.
5. No Omarchy, clique no relógio na barra para abrir o calendário.
6. Pressione `S` (ou clique no ícone de engrenagem no topo do painel).
7. Cole o link no campo **"URL secreta iCal (.ics) do Google Calendar"** e clique em
   **"Salvar e Sincronizar"** (ou pressione Enter).

Em poucos segundos os seus eventos aparecem nas visões Dia, Semana, Mês e Ano.

Pelo terminal, o mesmo resultado: `omarchy-gcal set-ics 'https://calendar.google.com/calendar/ical/.../basic.ics'`.

---

## Opção 2: OAuth2 do Google Cloud (bidirecional)

Ideal se você quer que os eventos criados no Omarchy (pelo botão `+ Event`, pela tecla
`N` ou pelo comando `omarchy-gcal add`) sejam salvos direto no Google e apareçam no
celular, no tablet e no navegador.

### Passo 1: criar um projeto no Google Cloud (gratuito)
1. Acesse o [Google Cloud Console](https://console.cloud.google.com/) e entre com a sua
   conta do Google.
2. No topo da tela, clique no seletor de projetos e em **"Novo projeto"** (ou acesse
   direto [console.cloud.google.com/projectcreate](https://console.cloud.google.com/projectcreate)).
3. Preencha:
   - **Nome do projeto:** `Omarchy Calendar` (qualquer nome serve)
   - **Organização:** deixe **"Sem organização"**. Em contas pessoais (`@gmail.com`)
     esse é o padrão e não é preciso mudar nada.
4. Clique em **"Criar"** e confira se o novo projeto está selecionado no topo da página.

### Passo 2: ativar a API do Google Calendar
1. No menu lateral (ou na busca do topo), vá em **"APIs e serviços" > "Biblioteca"** (ou
   abra direto a [página da API](https://console.cloud.google.com/marketplace/product/google/calendar-json.googleapis.com)).
2. Clique em **"Ativar"**.

### Passo 3: configurar a Google Auth Platform (tela de consentimento)
1. No menu lateral, clique em **"Google Auth Platform"** (ou "Tela de permissão OAuth").
2. **Informações do app:**
   - **Nome do app:** `Omarchy Calendar`
   - **E-mail de suporte** e **e-mail do desenvolvedor:** o seu.
   - Clique em **Próxima** / **Salvar e continuar**.
3. **Público-alvo (Audience):** selecione **"Externo"** (contas pessoais `@gmail.com`
   usam Externo) e avance.
4. **Usuários de teste:** em **"Audience"**, na seção **"Test users"**, clique em
   **"+ Add users"**, digite o seu e-mail do Google e confirme. *(Obrigatório: enquanto o
   app estiver em modo de teste, só os usuários de teste conseguem entrar.)*
5. **Acesso a dados / escopos:** se for pedido, adicione o escopo `.../auth/calendar`.

### Passo 4: criar o cliente OAuth
1. No menu lateral, clique em **"Clients"** (ou "Credenciais").
2. Clique em **"+ Create Client"** (ou "+ Criar credenciais" > "ID do cliente OAuth").
3. Em **Tipo de aplicativo**, escolha **"App para computador"** (*Desktop app*).
4. Em **Nome**, digite `Omarchy Shell`.
5. Se aparecer a opção *"Use this client for an AI-powered agent"*, **deixe desmarcada**.
6. Clique em **"Criar"**.
7. Na janela seguinte, clique em **"Download JSON"**. O arquivo `client_secret_...json`
   vai para a sua pasta `~/Downloads`.

### Passo 5: conectar ao Omarchy (um comando)
Com o arquivo em `~/Downloads`, abra um terminal e rode:

```bash
omarchy-gcal auth
```

O `omarchy-gcal` encontra sozinho o `client_secret_*.json` mais recente em `~/Downloads`
e o copia para `~/.config/omarchy/gcal/credentials.json`: não é preciso renomear nada.
Para indicar o arquivo manualmente:

```bash
omarchy-gcal auth --credentials-file ~/Downloads/client_secret_XXXX.json
```

> **Pela interface:** copie o arquivo para `~/.config/omarchy/gcal/credentials.json`:
> ```bash
> mkdir -p ~/.config/omarchy/gcal
> cp ~/Downloads/client_secret_*.json ~/.config/omarchy/gcal/credentials.json
> ```
> Depois abra o calendário, pressione `S` e clique em **"Iniciar autenticação OAuth2"**.

### Passo 6: autorizar no navegador
1. Uma aba abre sozinha no navegador. Escolha a sua conta do Google.
2. Se aparecer *"O Google não verificou este app"*, clique em **"Avançado" > "Acessar
   Omarchy Calendar (não seguro)"**. É normal: o app é seu, criado em modo de teste.
3. Marque a permissão para ver e editar a sua agenda e clique em **"Continuar"**.
4. O navegador mostra *"Google Calendar is connected to Omarchy."*

Pronto. Os tokens são renovados automaticamente em segundo plano.

---

## Comandos úteis no terminal

```bash
# Status da conexão e número de eventos
omarchy-gcal status

# Forçar uma sincronização agora
omarchy-gcal sync

# Próximos eventos, ou os de um dia
omarchy-gcal list --upcoming
omarchy-gcal list --date today

# Buscar eventos por palavra
omarchy-gcal list -q "Reunião"

# Criar um evento pelo terminal (com OAuth2, vai para o Google)
omarchy-gcal add --title "Reunião de equipe" --date 2026-11-10 --start 14:00 --end 15:00 --location "Google Meet"
```
