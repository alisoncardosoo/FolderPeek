# Folder Peek

O Folder Peek é um app gratuito de Quick Look para macOS que permite visualizar o conteúdo de pastas e arquivos compactados diretamente no Finder.

## O que ele inclui

- App principal nativo em SwiftUI para macOS.
- Extensão de Quick Look para pré-visualização de pastas.
- Tabela no estilo Finder com nome, tipo, tamanho, data de modificação e caminho relativo.
- Framework compartilhado e testável `FolderPeekCore`.
- Listagem de ZIP por meio de um leitor seguro de central directory no core compartilhado, pronto para ser reativado quando os UTTypes de archive forem finalizados.

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
xcodebuild -project FolderPeek.xcodeproj -target FolderPeekCoreTests -configuration Debug CODE_SIGNING_ALLOWED=NO test
```

## Habilitar a extensão

1. Abra o Folder Peek uma vez.
2. Use o ícone da barra de menu do Folder Peek e escolha **Mostrar app no Finder** se precisar localizar o app.
3. Abra os Ajustes do Sistema.
4. Vá em Geral > Itens de Início e Extensões > Quick Look.
5. Ative a extensão Folder Peek Quick Look Extension.
6. No Finder, selecione uma pasta e pressione Espaço.

O app também possui um botão para abrir direto os ajustes de Extensões.
