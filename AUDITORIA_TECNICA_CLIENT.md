# Documento de Auditoria Técnica — Agente Responsável pelo Cliente (`rustdesk`)

> **Destinatário:** Agente de IA responsável por `C:\Users\Suporte01\Documents\Projeto Padrão\RustDesk\rustdesk`
> **Escopo:** Código customizado em Rust, Dart/Flutter, C/C++ e Scripts de Build/CI (`InTimeDesk`)
> **Objetivo desta comunicação:** Analisar rigorosamente os apontamentos abaixo. Você tem total autonomia técnica para **refutar com evidências e justificativas arquiteturais/de negócio** qualquer ponto com o qual discorde, ou **concordar com o Plano de Ação** (integral ou parcialmente) antes de iniciar a execução.

---

## Como você (Agente `rustdesk`) deve responder a este documento

Para cada item numerado (`[CLIENT-01]` a `[CLIENT-06]`), responda utilizando estritamente a estrutura abaixo:
1. **Veredito do Agente:** `[CONCORDO]` | `[REFUTO]` | `[CONCORDO PARCIALMENTE]`
2. **Argumentação Técnica / Evidência:** Se refutar ou concordar parcialmente, explique o requisito de negócio ou restrição técnica do RustDesk/Flutter que motivou a implementação atual (ex.: requisito explícito do cliente para senha mestra de suporte, limitações do `flutter_rust_bridge`, ou comportamento do `hbbs` open-source).
3. **Ação Proposta:** Confirme se aplicará o código corrigido sugerido ou proponha uma alternativa mais adequada à arquitetura do cliente.

---

## 1. RELATÓRIO DE AUDITORIA (`rustdesk`)

### [CLIENT-01] Senha Mestra Hardcoded em Texto Puro no Binário e Bypass de Aprovação (`ApproveMode::Click`)
- **Nível de Gravidade:** Bloqueante (Segurança)
- **Arquivos e Funções Afetadas:**
  - `Connection::validate_password` (linhas 2625–2636) e `Connection::on_login_msg` (linhas 3060–3117) em `src/server/connection.rs`
  - `checkUnlockPinDialog` (linhas 2773–2780) em `flutter/lib/common/widgets/dialog.dart`
  - `showServerSettingsWithValue` (linhas 237–249) em `flutter/lib/mobile/widgets/dialog.dart`
  - `patch_custom_config` (linhas 93–114) em `build.rs` e `res/patch-custom.py` (linhas 10–18)
- **O que está errado:**
  1. A string literal `@#intimetec#@` está compilada diretamente nos binários Rust e Dart. Qualquer execução de `strings InTimeDesk.exe` ou inspeção do bundle Flutter revela a senha mestra.
  2. Em `Connection::on_login_msg` (`src/server/connection.rs`), a autenticação via `@#intimetec#@` contorna o modo `ApproveMode::Click` e força todas as permissões críticas (`keyboard`, `clipboard`, `audio`, `file`, `restart`, `recording`, `block_input`, `privacy_mode`) como `true`, mesmo quando o usuário local configurou restrições.
  3. Caso a senha mestra seja um **requisito obrigatório de negócio** da In Time Technology para suporte não supervisionado, ela jamais deve ser comparada em texto puro hardcoded em múltiplos arquivos nem usar a mesma string de desbloqueio de PIN local.
- **Código Corrigido (Recomendado):**
  Se o acesso não supervisionado deve respeitar o mecanismo criptográfico nativo do RustDesk, remova o bypass em texto puro ou substitua por verificação de hash SHA-256/Argon2 com salt em variável de ambiente de build (`option_env!`), sem expor a senha em texto plano no binário:
  ```rust
  // src/server/connection.rs
  fn validate_password(&mut self, allow_permanent_password: bool) -> bool {
      if password::temporary_enabled() {
          let password = password::temporary_password();
          if self.validate_password_plain(&password) {
              self.set_conn_audit_primary_auth(ConnAuditPrimaryAuth::TemporaryPassword);
              raii::AuthedConnID::update_or_insert_session(
                  self.session_key(),
                  Some(password),
                  Some(false),
              );
              return true;
          }
      }
      if allow_permanent_password && password::permanent_enabled() {
          if self.validate_password_hash(&Config::get_permanent_password()) {
              self.set_conn_audit_primary_auth(ConnAuditPrimaryAuth::PermanentPassword);
              raii::AuthedConnID::update_or_insert_session(
                  self.session_key(),
                  Some(Config::get_permanent_password()),
                  Some(true),
              );
              return true;
          }
      }
      false
  }
  ```

---

### [CLIENT-02] Auto-Modificação de Código-Fonte Rastreado Durante o Build (`build.rs` e `patch-custom.py`)
- **Nível de Gravidade:** Alta (Arquitetura, SOLID e Performance de Compilação)
- **Arquivos e Funções Afetadas:**
  - `patch_custom_config` (linhas 93–114) em `build.rs`
  - `res/patch-custom.py` (linhas 1–21)
- **O que está errado:**
  1. `build.rs` do pacote principal modifica diretamente `libs/hbb_common/src/config.rs` (uma sub-crate já compilada antes ou em paralelo pelo Cargo) usando `String::replace`.
  2. Como `build.rs` da crate raiz roda **depois** que a dependência `hbb_common` já foi compilada no primeiro build limpo, a primeira compilação pode usar os valores antigos de `hbb_common` a menos que `res/patch-custom.py` tenha rodado antes!
  3. Além disso, há duplicação exata da lógica de substituição entre `build.rs` (Rust) e `res/patch-custom.py` (Python), violando DRY e sujando a árvore Git (`git status`) localmente.
- **Código Corrigido:**
  Versione as constantes diretamente em `libs/hbb_common/src/config.rs` usando `option_env!` (permitindo override via CI/CD sem modificar arquivos no disco) e remova `patch_custom_config()` de `build.rs`:
  ```rust
  // libs/hbb_common/src/config.rs
  lazy_static::lazy_static! {
      pub static ref APP_NAME: RwLock<String> = RwLock::new(
          option_env!("INTIMEDESK_APP_NAME").unwrap_or("InTimeDesk").to_owned()
      );
      pub static ref PROD_RENDEZVOUS_SERVER: RwLock<String> = RwLock::new(
          option_env!("INTIMEDESK_ID_SERVER").unwrap_or("itdesk.intimelab.com.br").to_owned()
      );
  }
  pub const PUBLIC_RS_PUB_KEY: &str = match option_env!("INTIMEDESK_PUB_KEY") {
      Some(k) => k,
      None => "xRuoiQZq8Xc4qRfCypofM63dtL6ZLJSrhzQiwjrRpsg=",
  };
  ```

---

### [CLIENT-03] Remoção de `callMainCheckSuperUserPermission` ao Desbloquear Configurações Desktop
- **Nível de Gravidade:** Média (Segurança e Arquitetura)
- **Arquivos e Funções Afetadas:**
  - `_lock` (linhas 3065–3070) em `flutter/lib/desktop/pages/desktop_setting_page.dart`
- **O que está errado:**
  O código original verificava `callMainCheckSuperUserPermission()` (UAC/polkit do sistema operacional) quando o PIN de desbloqueio estava vazio ou desabilitado. A alteração substituiu todo o bloco por `checkUnlockPinDialog(unlockPin, onUnlock)` combinado com o PIN mestre hardcoded `@#intimetec#@`. Isso impede que um administrador legítimo do Windows/Linux desbloqueie as configurações via elevação nativa do SO caso não conheça a string hardcoded.
- **Código Corrigido:**
  ```dart
  onPressed: () async {
    final unlockPin = bind.mainGetUnlockPin();
    if (unlockPin.isNotEmpty) {
      checkUnlockPinDialog(unlockPin, onUnlock);
    } else {
      bool checked = await callMainCheckSuperUserPermission();
      if (checked) {
        onUnlock();
      }
    }
  },
  ```

---

### [CLIENT-04] Supressão Hardcoded do `access_token` no `io_loop` e Handshake `secure_tcp`
- **Nível de Gravidade:** Média (Arquitetura e Acoplamento)
- **Arquivos e Funções Afetadas:**
  - `io_loop` (linhas 1980–1981) em `src/ui_session_interface.rs`
  - `Client::start` (linha 862) e `Client::connect_rendezvous` (linha 1810) em `src/client.rs`
- **O que está errado:**
  No commit `355ecb11c`, `let token = "";` foi chumbado em `io_loop` e a condição `!token.is_empty()` foi removida de `client.rs` para evitar que o `hbbs` open-source sofresse timeout ao tentar `secure_tcp` quando o usuário faz login na API web. Embora resolva o sintoma imediato no `hbbs` OSS, desativa permanentemente a autenticação por token no canal de rendezvous caso o servidor seja atualizado para validar tokens.
- **Código Corrigido:**
  Parametrizar o comportamento via opção ou constante de configuração documentada, mantendo a intenção clara e reversível:
  ```rust
  // src/ui_session_interface.rs
  let token = if Config::get_option("rendezvous-use-access-token") == "Y" {
      LocalConfig::get_option("access_token")
  } else {
      String::new()
  };
  ```

---

### [CLIENT-05] Memory Leak de `TextEditingController` e Duplicação de Padding Base64 no Flutter
- **Nível de Gravidade:** Média (Performance / Memory Leak e Clean Code)
- **Arquivos e Funções Afetadas:**
  - `showServerSettingsWithValue` (linhas 103–106 e 234–265) em `flutter/lib/mobile/widgets/dialog.dart`
  - `ServerConfig` (linhas 2972–2976) e `ServerConfig.fromOptions` (linhas 3017–3026) em `flutter/lib/common.dart`
- **O que está errado:**
  1. Em `showServerSettingsWithValue`, `final pinCtrl = TextEditingController();` (linha 234) e os 4 controllers principais (`idCtrl`, `relayCtrl`, `apiCtrl`, `keyCtrl`, linhas 78–81) são instanciados a cada abertura do diálogo sem chamada a `.dispose()` no fechamento, causando vazamento de memória (memory leak).
  2. O loop `while (k.isNotEmpty && k.length % 4 != 0) { k += '='; }` está triplicado em três lugares diferentes. Além disso, uma string Base64 com `length % 4 == 1` é **estruturalmente inválida** em Base64 (adicionar `===` não produz Base64 válido).
  3. Strings de UI em português (`'Desbloqueie com a senha mestre para alterar'`, `'Desbloquear com Senha Mestre'`, `'Configurações desbloqueadas'`) estão hardcoded em vez de passarem pela função `translate(...)`.
- **Código Corrigido:**
  ```dart
  // Centralizar em ServerConfig (flutter/lib/common.dart):
  static String normalizeBase64Key(String? rawKey, {String fallback = ''}) {
    var k = (rawKey ?? '').trim();
    if (k.isEmpty) k = fallback;
    final rem = k.length % 4;
    if (k.isNotEmpty && rem >= 2) {
      k = k.padRight(k.length + (4 - rem), '=');
    }
    return k;
  }
  ```

---

### [CLIENT-06] Verificação Case-Insensitive Redundante em `copy_exe_cmd` (Windows)
- **Nível de Gravidade:** Baixa (Qualidade e Clean Code)
- **Arquivos e Funções Afetadas:**
  - `copy_exe_cmd` (linhas 1525–1531) em `src/platform/windows.rs`
- **O que está errado:**
  As linhas adicionadas (`if not exist "{exe}" if exist "{path}\rustdesk.exe" move /Y ...` e `if exist "{path}\RustDesk.exe" move /Y ...`) são redundantes no NTFS por padrão (case-insensitive no Windows) e executam duas verificações de I/O idênticas seguidas.
- **Código Corrigido:**
  ```rust
  if not exist \"{exe}\" if exist \"{path}\\rustdesk.exe\" move /Y \"{path}\\rustdesk.exe\" \"{exe}\"
  if not exist \"{exe}\" if exist \"{src_exe}\" copy /Y \"{src_exe}\" \"{exe}\"
  ```

---

## 2. PLANO DE AÇÃO EM ETAPAS (`rustdesk`)

### Etapa 1 (Correções Críticas de Segurança e Build)
1. **[CLIENT-01]** Definir junto ao responsável do projeto se a senha mestra `@#intimetec#@` deve ser removida ou substituída por validação baseada em hash criptográfico sem exposição de texto puro no binário e sem sobrescrever `ApproveMode::Click` indevidamente.
2. **[CLIENT-02]** Remover a mutação de código-fonte em `build.rs` e `res/patch-custom.py`, consolidando as configurações customizadas diretamente em `libs/hbb_common/src/config.rs` via `option_env!`.

### Etapa 2 (Arquitetura e Segurança de Permissões Locais)
1. **[CLIENT-03]** Restaurar o fallback de `callMainCheckSuperUserPermission()` em `desktop_setting_page.dart` quando não houver PIN local configurado.
2. **[CLIENT-04]** Tornar configurável o envio ou omissão do `access_token` ao servidor de rendezvous em `ui_session_interface.rs`.

### Etapa 3 (Clean Code, Internacionalização e Memory Leaks no Flutter)
1. **[CLIENT-05]** Extrair `ServerConfig.normalizeBase64Key` em `common.dart`, substituir textos chumbados por `translate(...)` e descartar (`dispose`) os `TextEditingController` criados nos diálogos.
2. **[CLIENT-06]** Remover a linha duplicada case-insensitive em `src/platform/windows.rs`.
