# Relatório Técnico de Diagnóstico e Plano de Ação

**Documento:** `RELATORIO_TECNICO_ERROS_E_ACOES.md`  
**Projeto:** InTimeDesk (Cliente de Conexão Remota) & InTimeDesk-Server  
**Responsável Técnico:** Engenheiro de Software / Revisor Sênior  
**Destinatário:** Auditor Técnico / Equipe de QA  
**Data:** 06 de Novembro de 2026  
**Status:** `APROVADO PELO AUDITOR COM SALVAGUARDAS TÉCNICAS OBRIGATÓRIAS (SEÇÃO 7)`  

---

## 1. Sumário Executivo

Após a validação em ambiente de testes com os novos executáveis gerados a partir do commit `9604eb70f`, foram identificados dois comportamentos anômalos reportados pela equipe de testes com evidências fotográficas:

1. **Erro de Chaves Incompatíveis (`Key mismatch`):** A conexão com qualquer parceiro remoto falha na primeira tentativa em instalações limpas, sendo contornada apenas se o usuário abrir o diálogo de configurações, apagar a chave, colá-la novamente e clicar em "OK".
2. **Falha na Atualização do Diretório (`HTTP 500, FormatException: Unexpected character <!doctype html>`):** Banner de erro em vermelho na tela inicial ao consultar a agenda de contatos via API do `InTimeDesk-Server`.

Este relatório apresenta a análise aprofundada de causa raiz com rastreamento no código-fonte e o plano de ação corretivo detalhado para aprovação antes de qualquer alteração.

---

## 2. Diagnóstico do Erro 1: Chaves Incompatíveis em Instalações Limpas

### 2.1. Evidência e Sintoma
- **Evidência:** Mensagem de erro *"Erro de conexão: Chaves incompatíveis"* ao tentar iniciar conexão para o ID remoto `1109154962`.
- **Comportamento Curioso:** Ao abrir a tela de *Configurações -> Rede -> Servidor ID/Relay*, o campo *Key* já exibe visualmente a chave correta `xRuoiQZq8Xc4qRfCypofM63dtL6ZLJSrhzQiwjrRpsg=`. Se o usuário apenas apagar a chave e colá-la novamente e clicar em **OK**, todas as conexões passam a funcionar instantaneamente.

### 2.2. Rastreamento e Causa Raiz no Código
A causa raiz decorre de uma divergência entre a camada de apresentação do Flutter e o motor de rede em Rust quando o aplicativo é recém-instalado:

1. **Estado Inicial do Arquivo de Configuração (`RustDesk2.toml`):**
   Em uma máquina com instalação limpa, o arquivo `RustDesk2.toml` não possui a chave `key` definida nas opções do usuário (`Config::get_option("key")` retorna string vazia `""`).
2. **Mecanismo de Resolução da Chave no Rust (`src/common.rs:2144-2153`):**
   Quando a conexão é iniciada, o método `crate::get_key(false)` busca a chave:
   ```rust
   let mut key = if sync {
       Config::get_option("key")
   } else {
       let mut options = crate::ipc::get_options_async().await;
       options.remove("key").unwrap_or_default()
   };
   if key.is_empty() {
       key = config::RS_PUB_KEY.to_owned();
   }
   ```
   Como `key` está vazio, o Rust recorre ao fallback compilado: `config::RS_PUB_KEY`.
3. **Origem da Constante `config::RS_PUB_KEY` (`libs/hbb_common/src/config.rs:117`):**
   No submódulo `libs/hbb_common/src/config.rs:117`, a constante está definida com a chave pública padrão do RustDesk oficial:
   ```rust
   pub const RENDEZVOUS_SERVERS: &[&str] = &["rs-ny.rustdesk.com"];
   pub const RS_PUB_KEY: &str = "OeVuKk5nlHiXp+APNn0Y3pC1Iwpwn44JGqrQCsWqmBw=";
   ```
   Anteriormente, tentava-se alterar esse arquivo via substituição de strings em scripts (`res/patch-custom.py`), que foram corretamente removidos por causarem race conditions e falhas de compilação. Sem a constante institucional estática, o binário foi compilado com a chave oficial upstream `OeVuKk5nl...`.
4. **Rejeição pelo Servidor `hbbs`:**
   O cliente conecta ao `hbbs` da In Time Technology (`itdesk.intimelab.com.br`) enviando no `PunchHoleRequest`:
   ```rust
   licence_key: "OeVuKk5nlHiXp+APNn0Y3pC1Iwpwn44JGqrQCsWqmBw="
   ```
   O servidor `hbbs` valida a chave contra sua chave pública configurada (`xRuoiQZq8Xc4qRfCypofM63dtL6ZLJSrhzQiwjrRpsg=`). Por haver divergência, o servidor rejeita o pacote com `punch_hole_response::Failure::LICENSE_MISMATCH`.
   Em `src/client.rs:1017`:
   ```rust
   match ph.failure.enum_value() {
       ...
       Ok(punch_hole_response::Failure::LICENSE_MISMATCH) => {
           bail!("Key mismatch"); // Exibido na interface como "Chaves incompatíveis"
       }
   ```
5. **Por que clicar em OK resolve?**
   No Flutter (`flutter/lib/common.dart:3017`), o construtor `ServerConfig.fromOptions` possui um fallback hardcoded:
   ```dart
   key = normalizeBase64Key(options['key']?.toString(),
       fallback: "xRuoiQZq8Xc4qRfCypofM63dtL6ZLJSrhzQiwjrRpsg=");
   ```
   O formulário exibe visualmente o fallback. Quando o usuário clica em "OK", o Flutter aciona `setServerConfig`, gravando fisicamente `key = "xRuoiQZq8Xc4qRfCypofM63dtL6ZLJSrhzQiwjrRpsg="` no `RustDesk2.toml`. A partir desse momento, `Config::get_option("key")` passa a retornar a chave correta e o fallback do Rust nunca mais é atingido.

---

## 3. Diagnóstico do Erro 2: Falha na Atualização do Diretório (HTTP 500)

### 3.1. Evidência e Sintoma
- **Evidência:** Banner superior em vermelho na interface principal:
  ```text
  Não foi possível atualizar o diretório: HTTP 500, FormatException: Unexpected character (at line 2, character 1)
  <!doctype html>
  ^
  ```
- **Contexto:** Ocorre quando o usuário está autenticado na plataforma e a interface tenta sincronizar os contatos da agenda de endereços com o servidor de API (`https://itdesksuport.intimelab.com.br`).

### 3.2. Rastreamento e Causa Raiz no Código

O problema é composto por dois fatores interdependentes (um no backend e outro na resiliência do frontend):

1. **Causa no Backend (`InTimeDesk-Server` / Django):**
   - Ao puxar a agenda de contatos, o cliente Flutter executa requisições `POST` em:
     - `/api/ab/settings` (`flutter/lib/models/ab_model.dart:233`)
     - `/api/ab/personal` (`flutter/lib/models/ab_model.dart:265`)
     - `/api/ab` (`flutter/lib/models/ab_model.dart:1010`)
   - Em `flutter/lib/models/ab_model.dart:236`, o cliente chama `_setEmptyBody(headers)` que define `headers['Content-Length'] = '0'` e `headers['Content-Type'] = 'application/json'`, mas **não envia payload** (`body: null`).
   - Nos frameworks Python/Django que atendem essa rota, se a view tentar executar `json.loads(request.body)` em um corpo vazio `""`, o interpretador lança a exceção fatal `json.decoder.JSONDecodeError: Expecting value: line 1 column 1 (char 0)`.
   - Como a exceção não é tratada na view do Django, o servidor retorna **HTTP 500 Internal Server Error** acompanhado de uma página HTML de depuração ou erro padrão do Django/Nginx (`<!doctype html>...`).
2. **Causa no Frontend (`ab_model.dart`):**
   - Em `flutter/lib/models/ab_model.dart:1976-1987`:
     ```dart
     Map<String, dynamic> _jsonDecodeRespMap(String body, int statusCode) {
       try {
         Map<String, dynamic> json = jsonDecode(body);
         return json;
       } catch (e) {
         final err = body.isNotEmpty && body.length < 128 ? body : e.toString();
         if (statusCode != 200) {
           throw 'HTTP $statusCode, $err';
         }
         throw err;
       }
     }
     ```
   - Como a resposta HTML possui mais de 128 caracteres, a variável `err` assume `e.toString()`, que é a mensagem interna do Dart `FormatException: Unexpected character (at line 2, character 1) <!doctype html>`.
   - O método `_setListPullError` recebe essa exceção e concatena diretamente com a chave traduzida `pull_ab_failed_tip`:
     ```dart
     _listPullError.value = '${translate('pull_ab_failed_tip')}: ${translate(err.toString())}';
     ```
   - O resultado é a exibição de uma mensagem técnica de baixo nível e antiestética na tela principal.

---

## 4. Plano de Ação Recomendado

### 4.1. Correção Definitiva do Erro 1 (Chaves Incompatíveis)
1. **Padronização Estática em `libs/hbb_common/src/config.rs`:**
   Alterar as constantes globais de fallback para refletirem os servidores e a chave pública da In Time Technology:
   ```rust
   pub const RENDEZVOUS_SERVERS: &[&str] = &["itdesk.intimelab.com.br"];
   pub const RS_PUB_KEY: &str = "xRuoiQZq8Xc4qRfCypofM63dtL6ZLJSrhzQiwjrRpsg=";
   ```
2. **Proteção Adicional de Fallback em `src/common.rs:2150`:**
   Garantir que a função `crate::get_key()` retorne a chave institucional `xRuoiQZq8Xc4qRfCypofM63dtL6ZLJSrhzQiwjrRpsg=` como valor padrão explícito, eliminando qualquer dependência de gravação prévia no disco.
3. **Consistência em `src/client.rs`:**
   Garantir que `src/client.rs:1662` e `src/client.rs:2927` utilizem a mesma chave padrão `xRuoiQZq8Xc4qRfCypofM63dtL6ZLJSrhzQiwjrRpsg=`.

### 4.2. Correção Definitiva do Erro 2 (Atualização do Diretório / HTTP 500)
1. **Resiliência e Payload Válido no Cliente Flutter (`flutter/lib/models/ab_model.dart`):**
   - Em todas as chamadas `http.post(Uri.parse(api), headers: headers)` que definem `Content-Type: application/json` (linhas 237, 269, 318, etc.), enviar explicitamente um corpo JSON vazio válido:
     ```dart
     body: "{}",
     ```
     Isso impede que backends Django/FastAPI/Flask lancem `JSONDecodeError` ao tentar desserializar o corpo da requisição.
   - Refatorar `_jsonDecodeRespMap`: se `statusCode != 200` e a resposta contiver marcadores de HTML (`<html` ou `<!doctype`), suprimir o erro de `FormatException` e gerar uma mensagem limpa e descritiva:
     ```dart
     if (statusCode == 500) {
       throw 'HTTP 500: Erro interno no servidor da API';
     }
     ```
   - Adicionar tratamento de fallback gracioso: se o endpoint `/api/ab/settings` retornar 500 ou 404, registrar o log no console de desenvolvimento (`debugPrint`) e permitir que o cliente continue funcionando sem travar a interface de catálogo de contatos com erro fatal.
2. **Recomendação para o Backend `InTimeDesk-Server` (Servidor Django):**
   - Verificar os logs em `https://itdesksuport.intimelab.com.br` para a rota `/api/ab/settings`.
   - Assegurar que as views de Address Book utilizem tratamento seguro para corpo vazio:
     ```python
     data = json.loads(request.body.decode('utf-8') or '{}')
     ```

---

## 5. Matriz de Risco e Impacto

| Mudança | Risco | Mitigação |
| :--- | :---: | :--- |
| Atualizar fallback `RS_PUB_KEY` no Rust | **Mínimo** | A chave utilizada é idêntica à que o servidor `itdesk.intimelab.com.br` já exige. Não afeta usuários existentes com `RustDesk2.toml` já configurado e resolve 100% dos novos usuários. |
| Adicionar `body: "{}"` em requisições POST do Flutter | **Nulo** | Enviar `{}` é o padrão universal para chamadas JSON POST sem parâmetros, compatível com qualquer biblioteca backend. |
| Sanitização de erro HTTP 500 no Flutter | **Nulo** | Não altera a lógica de negócios; apenas previne que exceções cruas de formatação HTML apareçam em texto puro para o cliente final. |

---

## 6. Solicitação de Parecer / Aval do Auditor

Submetemos este relatório técnico à auditoria para:
1. Validação das causas raízes apresentadas.
2. Autorização formal para execução das alterações listadas na Seção 4 no repositório do cliente `InTimeDesk`.

*Nenhuma linha de código foi alterada nesta etapa, conforme diretriz de conformidade da auditoria.*

---

## 7. Aval Oficial do Auditor Sênior e Salvaguardas Críticas (`APROVADO`)

**Decisão:** **APROVADO PARA EXECUÇÃO IMEDIATA**, observando obrigatoriamente as 3 salvaguardas arquiteturais abaixo durante a codificação:

### ⚠️ Salvaguarda 1 (Crítica para o CI/CD GitHub Actions — Erro 1: `Key mismatch`)
- **Atenção ao Submódulo Git (`libs/hbb_common`):** O diretório `libs/hbb_common` está registrado em `.gitmodules` apontando para o repositório oficial externo (`https://github.com/rustdesk/hbb_common`). Portanto, **qualquer alteração feita apenas dentro de `libs/hbb_common/src/config.rs` NÃO é enviada pelo `git push origin master` do repositório principal** e será sobrescrita quando o GitHub Actions executar o checkout do submódulo no build!
- **Como implementar de forma 100% persistente no repositório principal (`src/`):**
  1. Defina as constantes institucionais diretamente em `src/common.rs` (que faz parte do repositório principal `rustdesk`):
     ```rust
     pub const INTIMEDESK_RS_PUB_KEY: &str = "xRuoiQZq8Xc4qRfCypofM63dtL6ZLJSrhzQiwjrRpsg=";
     pub const INTIMEDESK_RENDEZVOUS_SERVER: &str = "itdesk.intimelab.com.br";
     ```
  2. Em `src/common.rs:2150` (`get_key`), faça:
     ```rust
     if key.is_empty() || key == config::RS_PUB_KEY {
         key = INTIMEDESK_RS_PUB_KEY.to_owned();
     }
     ```
  3. Em `src/client.rs:1661` (`secure_connection`) e `src/client.rs:2927`:
     Substitua `config::RS_PUB_KEY` por `crate::common::INTIMEDESK_RS_PUB_KEY` (e trate `if key.is_empty() || key == config::RS_PUB_KEY` em `secure_connection`).
  4. Em `src/client.rs:480`:
     Substitua `RENDEZVOUS_SERVERS[0]` por `crate::common::INTIMEDESK_RENDEZVOUS_SERVER`.
  *(Você também pode atualizar `libs/hbb_common/src/config.rs` localmente para builds locais, mas a resolução em `src/common.rs` e `src/client.rs` é o que garante que o binário gerado no GitHub Actions nunca mais caia na chave upstream `OeVuKk5nl...`).*

### ⚠️ Salvaguarda 2 (Conflito de `Content-Length: 0` em `ab_model.dart` — Erro 2)
- **Atenção a `_setEmptyBody(headers)` (`flutter/lib/models/ab_model.dart:2029`):**
  A função `_setEmptyBody(headers)` define explicitamente `headers['Content-Length'] = '0'`.
  Se você adicionar `body: "{}"` (2 bytes) em `http.post(...)` mantendo `_setEmptyBody(headers)`, o cabeçalho `Content-Length: 0` entrará em conflito com o corpo de 2 bytes `"}"`, causando erro de protocolo HTTP (`400 Bad Request`) no Cloudflare/Gunicorn!
- **Causa Real do HTTP 500 no Servidor (Já identificada na Auditoria do Servidor):**
  O `views_api.py` do servidor já trata corpo vazio com segurança (`body_str = request.body.decode('utf-8').strip() if request.body else ''`). O erro `HTTP 500 <!doctype html>` em `POST /api/ab/personal` ocorreu porque `api/urls.py` no servidor estava com regex de grupo de captura `r'^ab(/.*)?$'` em vez de não-captura `r'^ab(?:/.*)?$'`, passando um segundo argumento posicional `'/personal'` para `def ab(request):` (`TypeError: ab() takes 1 positional argument but 2 were given`). Isso já foi homologado para correção no servidor.
- **O que fazer em `flutter/lib/models/ab_model.dart`:**
  1. **Não** envie `body: "{}"` junto com `_setEmptyBody(headers)` (mantenha o `_setEmptyBody(headers)` original sem `body`, ou remova `_setEmptyBody(headers)` se enviar `body`).
  2. Aplique a **sanitização de erro HTML em `_jsonDecodeRespMap`** (`ab_model.dart:1976`) para nunca exibir `<!doctype html>` na tela.
  3. Em `_getPersonalAbGuid` (`ab_model.dart:271`), se `statusCode == 404 || statusCode == 500`, faça fallback gracioso para o modo legado (`_personalAbGuid = null; return true;`) em vez de abortar a sincronização de contatos (`GET /api/ab`).
