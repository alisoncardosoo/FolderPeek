<div align="center">
  <img src="./FolderPeek/Resources/Assets.xcassets/FolderPeekLogo.imageset/logo.png" width="120" alt="Logo do Folder Peek" />

# Folder Peek

### Pré-visualize pastas e arquivos compactados no Quick Look do macOS

![Status](https://img.shields.io/badge/status-ativo-success)
![Plataforma](https://img.shields.io/badge/plataforma-macOS%2014%2B-black)
![Swift](https://img.shields.io/badge/Swift-6.0-orange)
![Versão](https://img.shields.io/badge/vers%C3%A3o-1.3-blue)
![Stars](https://img.shields.io/github/stars/alisoncardosoo/FolderPeek?style=social)
![Forks](https://img.shields.io/github/forks/alisoncardosoo/FolderPeek?style=social)
![Issues](https://img.shields.io/github/issues/alisoncardosoo/FolderPeek)
![Last Commit](https://img.shields.io/github/last-commit/alisoncardosoo/FolderPeek)
![License](https://img.shields.io/badge/license-n%C3%A3o%20definida-lightgrey)
![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen)

</div>

## 📚 Índice

- [Sobre](#-sobre)
- [Status do projeto](#-status-do-projeto)
- [Funcionalidades](#-funcionalidades)
- [Demonstração visual](#-demonstração-visual)
- [Acesso ao projeto](#-acesso-ao-projeto)
- [Instalação e uso](#-instalação-e-uso)
- [Tecnologias utilizadas](#-tecnologias-utilizadas)
- [Arquitetura](#-arquitetura)
- [Roadmap](#-roadmap)
- [Contribuição](#-contribuição)
- [Autor](#-autor)
- [Licença](#-licença)

## 🚀 Sobre

O **Folder Peek** é um app gratuito para macOS que adiciona uma experiência de preview rica no Finder via **Quick Look**. Ele resolve o problema de navegação rápida em estruturas de pastas e arquivos compactados, sem precisar abrir vários apps ou extrair conteúdo manualmente.

O projeto é voltado para pessoas desenvolvedoras e usuários avançados de macOS que precisam inspecionar conteúdo com velocidade, contexto e segurança.

## 📌 Status do projeto

🟢 **Ativo / Em evolução contínua**

- Versão atual do app: **1.3 (build 4)**
- Canal de atualização: **Sparkle (estável)**

## 🔨 Funcionalidades

### App principal (SwiftUI)

- Interface nativa para macOS.
- Abertura rápida do app instalado e atalhos para ajustes de extensão.
- Aba de doação com PIX, QR Code e ação de copiar chave.
- Chave PIX do projeto: `d6d63f9b-5e12-4b96-8f33-d2b83a23e86d`.

### Bandeja temporária (Dropover/Yoink-style)

- Janela flutuante única (sem abas) para segurar múltiplos arquivos temporariamente.
- Layout simples em grade, focado em arrastar itens para dentro e para fora.
- Gatilho automático ao detectar arrasto de arquivos no Finder.
- A bandeja abre colada ao lado direito do Finder quando possível.
- Atalho global padrão para abrir/ocultar: `Control + Option + Space`.
- Observação V1: selecionar múltiplos arquivos sem arrastar não abre a bandeja automaticamente.

### Extensão Quick Look

- Preview de pastas direto no Finder.
- Suporte a tipos: `public.directory`, `public.folder`, ZIP/TAR/GZIP/7z/RAR (UTTypes declarados).

### Núcleo compartilhado (`FolderPeekCore`)

- Tabela estilo Finder com: nome, tipo, tamanho, modificação e caminho relativo.
- Leitura segura de diretório central para listagem de ZIP.
- Base desacoplada para testes e evolução incremental.

### Build e distribuição

- Script único para build, assinatura ad-hoc, cópia para `dist/` e instalação em `/Applications`.
- Re-registro da extensão para reduzir fricção na validação local.

## 🖼 Demonstração visual

<div align="center">
  <img src="./FolderPeek/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512.png" width="180" alt="Ícone do Folder Peek" />
</div>

- App bundle gerado no repositório: `dist/FolderPeek.app`
- App instalado para uso no sistema: `/Applications/FolderPeek.app`

## 🌐 Acesso ao projeto

- Repositório: [github.com/alisoncardosoo/FolderPeek](https://github.com/alisoncardosoo/FolderPeek)
- Feed de atualização Sparkle: [docs/sparkle/appcast.xml](./docs/sparkle/appcast.xml)
- Build local principal: `./script/build_and_run.sh`

## ⚙️ Instalação e uso

### 1) Clonar repositório

```bash
git clone https://github.com/alisoncardosoo/FolderPeek.git
cd FolderPeek
```

### 2) Build e instalação automática

```bash
./script/build_and_run.sh
```

### 3) Instalação manual (alternativa)

1. Gere o app em `dist/FolderPeek.app`.
2. Copie para `/Applications/FolderPeek.app`.
3. Abra o app uma vez.

### 4) Ativar extensão Quick Look

1. Abrir **Ajustes do Sistema**.
2. Ir em **Geral > Itens de Início e Extensões > Quick Look**.
3. Ativar **Folder Peek Quick Look Extension**.
4. No Finder, selecionar uma pasta e pressionar **Espaço**.

### 5) Rodar testes

```bash
xcodebuild -project FolderPeek.xcodeproj -scheme FolderPeekCore -configuration Debug CODE_SIGNING_ALLOWED=NO test
```

### 6) Usar a bandeja temporária

1. No Finder, comece a arrastar arquivos para abrir a bandeja automaticamente.
2. Alternativa manual: pressione `Control + Option + Space`.
3. Solte os arquivos na bandeja.
4. Arraste os itens da bandeja para a pasta desejada no Finder.
5. A bandeja mantém apenas uma instância por vez (sem múltiplas janelas/abas).

### 7) Atualizações in-app com Sparkle

- Feed configurado em `FolderPeek/Resources/Info.plist`.
- Verificação automática diária (`SUScheduledCheckInterval=86400`).
- Chave pública já configurada em `SUPublicEDKey`.

Configuração inicial (uma vez):

1. Gere as chaves no seu Mac:
   ```bash
   /Users/alisoncardoso/Library/Developer/Xcode/DerivedData/FolderPeek-djcatetzbxrspeaxlcoailknpaet/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys --account folderpeek
   ```
2. Valide a chave pública gerada:
   ```bash
   /Users/alisoncardoso/Library/Developer/Xcode/DerivedData/FolderPeek-djcatetzbxrspeaxlcoailknpaet/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys --account folderpeek -p
   ```
3. Atualize `SUPublicEDKey` em `FolderPeek/Resources/Info.plist`.
4. Nunca publique com placeholder (`REPLACE_WITH_SPARKLE_PUBLIC_ED25519_KEY`).
5. Mantenha a chave privada fora do Git (keychain local ou segredo no CI).

Fluxo de release resumido:

```bash
/Users/alisoncardoso/Library/Developer/Xcode/DerivedData/FolderPeek-djcatetzbxrspeaxlcoailknpaet/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update --account folderpeek dist/FolderPeek.zip
/Users/alisoncardoso/Library/Developer/Xcode/DerivedData/FolderPeek-djcatetzbxrspeaxlcoailknpaet/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast dist
```

## 🧰 Tecnologias utilizadas

| Camada | Tecnologias |
|---|---|
| App Desktop | Swift, SwiftUI, AppKit |
| Preview Finder | Quick Look Preview Extension |
| Core compartilhado | FolderPeekCore (framework interno testável) |
| Build e distribuição | xcodebuild, codesign, ditto, pluginkit |
| Atualizações | Sparkle |

## 🏗 Arquitetura

```text
📦 Folder Preview
 ┣ 📂 FolderPeek                       # App macOS (SwiftUI)
 ┣ 📂 FolderPeekQuickLookExtension     # Extensão Quick Look
 ┣ 📂 FolderPeekCore                   # Núcleo compartilhado e testável
 ┣ 📂 FolderPeekCoreTests              # Testes do core
 ┣ 📂 script                           # Scripts de build/instalação
 ┣ 📂 docs                             # Appcast e docs de release
 ┗ 📂 dist                             # App bundle gerado
```

## 🛣 Roadmap

- [x] Preview de pastas direto no Finder
- [x] Listagem de ZIP via core compartilhado
- [x] Fluxo de build e instalação automatizado
- [x] Atualização in-app com Sparkle
- [ ] Screenshots/GIF da experiência completa
- [ ] Pipeline de release totalmente automatizado via CI

## 🤝 Contribuição

1. Faça um fork do projeto.
2. Crie uma branch descritiva: `feat/minha-melhoria`.
3. Commit com contexto claro.
4. Abra um Pull Request com descrição objetiva de problema/solução.

Antes de abrir PR:

- Rode testes locais.
- Evite hardcode de segredos.
- Mantenha mudanças focadas em um objetivo por PR.

## 👤 Autor

<div align="center">
  <img src="https://github.com/alisoncardosoo.png" width="96" style="border-radius:50%;" alt="Avatar de Alison Cardoso" />

**Alison Cardoso**

[GitHub](https://github.com/alisoncardosoo)
</div>

## 📄 Licença

Este repositório ainda não possui arquivo `LICENSE` versionado.
Até uma definição explícita, considere **todos os direitos reservados** ao autor.

---

<div align="center">
  Feito para acelerar a inspeção de arquivos no macOS com uma experiência nativa, simples e eficiente.
</div>
