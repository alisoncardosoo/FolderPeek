# Folder Peek

O Folder Peek é um app gratuito de Quick Look para macOS que permite visualizar o conteúdo de pastas e arquivos compactados diretamente no Finder.

Guia principal: este README em PT-BR.

## O que ele inclui

- App principal nativo em SwiftUI para macOS.
- Extensão de Quick Look para pré-visualização de pastas.
- Tabela no estilo Finder com nome, tipo, tamanho, data de modificação e caminho relativo.
- Framework compartilhado e testável `FolderPeekCore`.
- Listagem de ZIP por meio de um leitor seguro de central directory no core compartilhado, pronto para ser reativado quando os UTTypes de archive forem finalizados.

## Doação

Se o Folder Peek te ajudou, você pode apoiar o projeto com PIX:

- Chave PIX: `d6d63f9b-5e12-4b96-8f33-d2b83a23e86d`
- O app também exibe uma aba dedicada de doação com QR code e botão de copiar.

## Onde encontrar o app gerado

O app gerado também fica versionado no repositório em:

```text
dist/FolderPeek.app
```

## Como instalar

Você pode instalar de duas formas:

1. Copie `dist/FolderPeek.app` para `/Applications`.
2. Ou execute o script abaixo, que instala e abre a versão do usuário em `/Applications/FolderPeek.app`:

```sh
./script/build_and_run.sh
```

## Testes

```sh
xcodebuild -project FolderPeek.xcodeproj -scheme FolderPeekCore -configuration Debug CODE_SIGNING_ALLOWED=NO test
```

## Atualizacoes automaticas (Sparkle)

O Folder Peek agora usa Sparkle para atualizacao in-app (canal estavel).

- Feed configurado no `Info.plist`: `https://github.com/alisoncardosoo/FolderPeek/releases/latest/download/appcast.xml`
- Acao no menu: `Verificar atualizacoes…`
- Checagem automatica: ativa 1x por dia (`SUScheduledCheckInterval=86400`)

### Configuracao inicial (uma vez)

1. Gere as chaves do Sparkle no seu Mac:
   ```sh
   /path/to/generate_keys
   ```
2. Copie a chave publica e substitua `SUPublicEDKey` em `FolderPeek/Resources/Info.plist`.
3. Mantenha a chave privada fora do git (keychain local ou secret no CI).

### Fluxo de release (N -> N+1)

1. Atualize a versao do app:
   - `CFBundleShortVersionString`
   - `CFBundleVersion`
2. Gere build/arquivo assinado do app (`.app`) e empacote como `.zip` ou `.dmg`.
3. Gere entrada e assinatura do appcast com as ferramentas do Sparkle (`generate_appcast`).
4. Publique os assets no GitHub Releases.
5. Envie o `appcast.xml` gerado como asset com nome `appcast.xml`.
6. Valide o update partindo de uma versao antiga instalada.

Template de appcast: `docs/sparkle/appcast.xml`.

## Habilitar a extensão

1. Abra o Folder Peek uma vez.
2. Use o ícone da barra de menu do Folder Peek e escolha **Mostrar app no Finder** se precisar localizar o app.
3. Abra os Ajustes do Sistema.
4. Vá em Geral > Itens de Início e Extensões > Quick Look.
5. Ative a extensão Folder Peek Quick Look Extension.
6. No Finder, selecione uma pasta e pressione Espaço.

O app também possui um botão para abrir direto os ajustes de Extensões.
