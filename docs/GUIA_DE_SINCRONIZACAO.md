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
3. No topo da tela, clique no seletor de projetos e clique em **"Novo projeto"** (ou acesse direto [console.cloud.google.com/projectcreate](https://console.cloud.google.com/projectcreate)).
4. Preencha os campos da tela:
   - **Nome do projeto:** `Omarchy Calendar`
   - **Organização (Organization):** Deixe como **"Sem organização"** (*No organization*). Se você usa uma conta pessoal (`@gmail.com`), isso é o padrão e você **não precisa alterar nada** nesse campo.
5. Clique no botão azul **"Criar"** (*Create*).
6. Aguarde alguns segundos até a notificação de criação e certifique-se de que o novo projeto está selecionado no topo da página.

### Passo 2: Ativar a API do Google Calendar
1. No menu lateral (ou barra de busca do topo), vá em **"APIs e serviços" > "Biblioteca"** (ou acesse direto o [link da API](https://console.cloud.google.com/marketplace/product/google/calendar-json.googleapis.com)).
2. Clique no botão azul **"Ativar"** (*Enable*).

### Passo 3: Configurar a Autenticação no Google (Google Auth Platform / Tela de Consentimento)
O Google atualizou recentemente o console para a **Google Auth Platform**. Siga os passos abaixo na tela:

1. No menu lateral esquerdo, clique em **"Google Auth Platform"** (ou "Tela de permissão OAuth").
2. **App Information (Informações do aplicativo):**
   - **Nome do app:** `Omarchy Calendar`
   - **E-mail de suporte:** selecione o seu próprio e-mail.
   - **E-mail do desenvolvedor:** insira o seu e-mail.
   - Clique em **Salvar e continuar** / **Next**.
3. **Audience (Público-alvo):**
   - Selecione **"External"** (Externo). *(Contas pessoais `@gmail.com` utilizam External)*.
   - Clique em **Next** / Salvar.
4. **Adicionar Usuário de Teste (Test Users):**
   - No menu lateral, clique em **"Audience"** (ou na etapa "Test Users").
   - Na seção **"Test users"** (Usuários de teste), clique em **"+ Add users"**, digite o seu próprio e-mail do Google e confirme. *(Isso é obrigatório para sua conta pessoal ter permissão de login enquanto o app estiver em modo de teste)*.
5. **Data Access / Scopes (Acesso a dados / Escopos):**
   - Se solicitado, adicione o escopo `.../auth/calendar` (Google Calendar API).

### Passo 4: Criar as Credenciais (Clients / ID do cliente OAuth)
1. No menu lateral esquerdo, clique em **"Clients"** (ou "Credenciais" / *Credentials*).
2. Clique em **"+ Create Client"** (ou "+ Criar credenciais" > "ID do cliente OAuth").
3. Em **Tipo de aplicativo** (*Application type*), selecione **"Desktop app"** (*App para computador*).
4. Em **Nome**, digite `Omarchy Shell` e clique em **"Create"** (*Criar*).
5. Uma janela se abrirá com o cliente criado. Clique no botão **"Download JSON"** (ícone de download ⬇️).
6. O arquivo será salvo na sua pasta `~/Downloads` com um nome parecido com `client_secret_...json`.

### Passo 5: Conectar ao Omarchy (1 comando no terminal)
Com o arquivo na sua pasta `Downloads`, abra o seu terminal e execute apenas:

```bash
omarchy-gcal auth
```

> ⚡ **Detecção Automática:** O `omarchy-gcal` detecta sozinho o arquivo de credenciais mais recente na sua pasta `~/Downloads`, sem você precisar renomear nem digitar o caminho do arquivo!
>
> *(Se preferir especificar manualmente, você também pode rodar `omarchy-gcal auth --credentials-file ~/Downloads/client_secret_*.json`).*

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
