# Packaging Flatpak — io.github.jperon.diapo

## Prérequis

- `nix develop` (moonc disponible dans le flake)
- `flatpak` et `flatpak-builder`

## Build local

### 1. Générer l'archive source transpilée

```bash
cd packaging/flatpak
./make-src-tarball.sh
```

Cela transpile les sources MoonScript en Lua, puis produit `diapo-src.tar.gz`
(ignoré par git).

### 2. Installer le runtime Freedesktop

```bash
flatpak install -y flathub org.freedesktop.Platform//25.08 org.freedesktop.Sdk//25.08
```

### 3. Construire et installer l'application

```bash
cd packaging/flatpak
flatpak-builder --user --install --force-clean build io.github.jperon.diapo.yml
```

### 4. Lancer

```bash
flatpak run io.github.jperon.diapo testdata
```

## Notes importantes

### sha256 et commits figés

Les valeurs de hachage dans le manifeste `io.github.jperon.diapo.yml` ont été
fixées aux sources suivantes :

- **LuaJIT** : commit `9d145d2ca3db58493859c495489a0f08f627834f` de la branche
  `v2.1` (archive GitHub). Pour mettre à jour :
  ```bash
  nix store prefetch-file --json https://github.com/LuaJIT/LuaJIT/archive/<COMMIT>.tar.gz
  nix hash to-base16 <hash-sri>
  ```
- **raylib** : tag `5.5` — sha256 figé.
- **libfacedetection** : commit HEAD `3023e1289e3b85311632bcfd45c9895b4292778b`
  (branche main). Pour mettre à jour : `git ls-remote https://github.com/ShiqiYu/libfacedetection.git HEAD`

Avant toute soumission à Flathub, vérifier que ces valeurs correspondent aux
sources choisies et mettre à jour si nécessaire.

### diapo-src.tar.gz

Le fichier `diapo-src.tar.gz` est généré localement par `make-src-tarball.sh`
et est ignoré par git (`.gitignore`). Il doit être (re)généré avant chaque
build Flatpak.
