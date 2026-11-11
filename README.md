# InTimeDesk & InTimeDesk SOS

<p align="center">
  <img src="res/logo-header.svg" alt="InTimeDesk - In Time Technology" width="400"><br>
  <b>Solução Corporativa de Suporte e Acesso Remoto Seguro</b><br>
  <i>Desenvolvido por In Time Technology</i>
</p>

---

## 📌 Sobre a In Time Technology

A **In Time Technology** desenvolve e opera soluções corporativas de conectividade, monitoramento e suporte técnico com foco em alta disponibilidade, privacidade e segurança da informação.

O **InTimeDesk** é a plataforma proprietária de acesso remoto da In Time Technology, baseada em tecnologias de ponta em **Rust** e **Flutter**, operando sobre uma infraestrutura de servidores dedicados com criptografia ponta a ponta para garantir total confidencialidade nas operações de suporte e telemetria.

---

## 🚀 Os Aplicativos da Plataforma

A plataforma é dividida em dois perfis de aplicação complementares, atendendo tanto a equipe técnica quanto o cliente final:

### 1. 🖥️ InTimeDesk (Versão Completa / Profissional)

Destinado aos analistas de suporte, administradores de TI e equipes técnicas da In Time Technology.

* **Conexões Bidirecionais:** Permite tanto prestar suporte (controlar máquinas remotas) quanto receber conexões de outros técnicos.
* **Painel Completo de Controle:**
  * Transferência bidirecional de arquivos com explorador de diretórios dedicado.
  * Catálogo de endereços (Address Book) e histórico recente de computadores atendidos.
  * Suporte a múltiplos monitores com seleção individual e mapeamento de resolução.
  * Túnel TCP e encaminhamento de portas (Port Forwarding / RDP).
  * Chat em tempo real e compartilhamento de áudio/vídeo em alta definição.
* **Integração Nativa:** Conexão pré-configurada diretamente à rede de servidores institucionais da In Time Technology.

---

### 2. 🛡️ InTimeDesk SOS (Suporte Rápido / QuickSupport)

Destinado exclusivamente aos **clientes finais, clínicas, parceiros e colaboradores** que necessitam de atendimento imediato.

Inspirado no consagrado formato *QuickSupport*, o **InTimeDesk SOS** elimina qualquer complexidade operacional para o usuário leigo:

* **100% Portátil (Standalone):** Executável único que roda sem necessidade de instalação, permissões de administrador prévias ou serviços residentes em segundo plano.
* **Segurança Unidirecional (Incoming-Only):**
  * O aplicativo funciona **apenas para receber atendimento**.
  * Todos os recursos de saída (conectar em outros computadores, catálogo e configurações) são totalmente removidos da interface e bloqueados no motor central em Rust.
  * Impede qualquer tentativa de uso indevido para conexões não autorizadas.
* **Interface Simples e Limpa:**
  * Exibe claramente **Seu ID** e a **Senha Temporária** de atendimento.
  * Permite renovar a senha temporária com um único clique.
* **Atalho Rápido para WhatsApp:**
  * Botão *"Copiar Acesso para WhatsApp"* que gera o texto formatado com ID e Senha, pronto para envio direto à equipe de atendimento da In Time.
* **Zero Configuração:**
  * O servidor institucional e os certificados criptográficos vêm embutidos no binário, eliminando erros de digitação de portas ou servidores.
* **Encerramento Rápido:**
  * Botão *"Sair"* que finaliza a sessão e encerra instantaneamente qualquer comunicação em rede.

---

## 🔒 Arquitetura & Segurança

A segurança é o pilar central das soluções da In Time Technology:

* **Criptografia Ponta a Ponta:** Todo o tráfego de áudio, vídeo, teclado e arquivos utiliza criptografia de chave pública assimétrica (Ed25519) e cifras autenticadas (ChaCha20-Poly1305).
* **Servidores Próprios Dedicados:** Tráfego de sinalização (Rendezvous) e retransmissão segura (Relay) hospedados na infraestrutura institucional `itdesk.intimelab.com.br`, garantindo que os dados não trafeguem por servidores públicos desconhecidos.
* **Senhas Temporárias Dinâmicas:** Acesso temporário descartável que expira ao fechar o aplicativo ou mediante solicitação de nova chave.
* **Controle de Privilégios (UAC):** Suporte nativo à elevação de privilégios sob demanda para manutenções administrativas no Windows sem travar telas de sistema.

---

## 📦 Como Utilizar

### Execução no Windows

| Aplicativo | Nome do Arquivo | Modo de Operação |
| :--- | :--- | :--- |
| **InTimeDesk (Completo)** | `InTimeDesk.exe` | Abre a interface completa para técnicos e analistas. |
| **InTimeDesk SOS** | `InTimeDesk-SOS.exe` | Abre automaticamente no modo Suporte Rápido. |

> **Dica:** O binário detecta o modo SOS tanto pelo nome do arquivo contendo `sos` quanto pelo argumento de linha de comando:
> ```cmd
> InTimeDesk.exe --sos
> ```

### Execução no Linux

O aplicativo é compatível com distribuições modernas (Ubuntu, Debian, Fedora, Mint, openSUSE e Arch Linux):

```bash
# Execução da versão completa
./intimedesk

# Execução no modo SOS (Suporte Rápido)
./intimedesk --sos
```

---

## 🛠️ Tecnologias Utilizadas

* **Rust:** Motor de alto desempenho para captura de vídeo, codificação (VP8/VP9/AV1), áudio (Opus), controle de entrada e segurança de memória.
* **Flutter:** Interface gráfica moderna, responsiva e multiplataforma com aceleração por hardware.
* **GitHub Actions:** Pipeline automatizado de integração e compilação contínua (CI/CD) para geração dos artefatos oficiais.

---

## ⚖️ Conformidade e Privacidade

Este software é de uso exclusivo para fins profissionais e de suporte técnico autorizado pela **In Time Technology**. Qualquer acesso remoto requer autorização expressa do usuário detentor do equipamento mediante o fornecimento voluntário do ID e da senha temporária de sessão.

---

## 🤝 Reconhecimentos

O InTimeDesk é construído com base nas excelentes fundações tecnológicas abertas do projeto [RustDesk](https://github.com/rustdesk/rustdesk), customizado e mantido pela equipe de engenharia da **In Time Technology**.
