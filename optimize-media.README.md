# optimize-media — guide d'utilisation

Script PowerShell **non-destructif** qui génère des versions optimisées des
images et vidéos du site. Les originaux ne sont jamais modifiés.

## 1) Installation des outils (une seule fois)

Ouvre PowerShell **en administrateur** et exécute :

```powershell
# ffmpeg — obligatoire (images + vidéos)
winget install --id Gyan.FFmpeg -e

# cwebp — recommandé pour les WebP (sinon ffmpeg fait le boulot)
winget install --id Google.WebpCodec -e

# avifenc — recommandé pour les AVIF (sinon ffmpeg+libaom-av1, ~5× plus lent)
# Pas dispo dans winget. Option scoop :
#   scoop install libavif
# Ou télécharge le binaire ici : https://github.com/AOMediaCodec/libavif/releases
```

Vérifie que tout est dans le PATH :

```powershell
ffmpeg -version
cwebp -version
avifenc --version
```

## 2) Lancement

Depuis le dossier `website ability/` :

```powershell
# Tout faire (images + vidéos)
pwsh ./optimize-media.ps1

# Voir ce qui serait fait sans rien écrire
pwsh ./optimize-media.ps1 -DryRun

# Images seules
pwsh ./optimize-media.ps1 -Images

# Vidéos seules
pwsh ./optimize-media.ps1 -Videos

# Forcer la ré-encodage même si les sorties existent déjà
pwsh ./optimize-media.ps1 -Force

# Ajuster la qualité (défauts : WebP 80, AVIF 55, MP4 CRF 28, WebM CRF 32)
pwsh ./optimize-media.ps1 -WebpQuality 75 -VideoCrfMp4 30
```

Premier passage attendu : ~10-25 min selon CPU (les AVIF sont longs).
Idempotent : un second lancement saute tout ce qui existe déjà.

## 3) Ce qui est généré

### Pour chaque image `images/.../foo.jpg` :
```
foo-480w.webp    foo-480w.avif
foo-960w.webp    foo-960w.avif
foo-1440w.webp   foo-1440w.avif
foo.jpg          ← original, intact
```

### Pour chaque vidéo `video/foo.mp4` (et celles à la racine) :
```
foo.opt.mp4      ← H.264 ré-encodé, 720p max, sans audio (décoratives)
foo.webm         ← VP9, même chose
foo.poster.jpg   ← première frame, pour <video poster="...">
foo.mp4          ← original, intact
```

## 4) Câbler les nouveaux fichiers dans index.html

### Images : remplacer `<img>` par `<picture>`

**Avant :**
```html
<img src="images/image-web/197fa1f5d6f750052893057ad7f2d7ed.jpg"
     alt="" loading="lazy" decoding="async" />
```

**Après :**
```html
<picture>
  <source type="image/avif"
          srcset="images/image-web/197fa1f5d6f750052893057ad7f2d7ed-480w.avif 480w,
                  images/image-web/197fa1f5d6f750052893057ad7f2d7ed-960w.avif 960w,
                  images/image-web/197fa1f5d6f750052893057ad7f2d7ed-1440w.avif 1440w"
          sizes="(max-width: 768px) 100vw, 50vw">
  <source type="image/webp"
          srcset="images/image-web/197fa1f5d6f750052893057ad7f2d7ed-480w.webp 480w,
                  images/image-web/197fa1f5d6f750052893057ad7f2d7ed-960w.webp 960w,
                  images/image-web/197fa1f5d6f750052893057ad7f2d7ed-1440w.webp 1440w"
          sizes="(max-width: 768px) 100vw, 50vw">
  <img src="images/image-web/197fa1f5d6f750052893057ad7f2d7ed.jpg"
       alt="" loading="lazy" decoding="async"
       width="960" height="640" />
</picture>
```

Le navigateur prend automatiquement AVIF s'il sait, sinon WebP, sinon
l'original JPG. Aucun risque de régression.

> Astuce `sizes` : adapte selon la taille réelle d'affichage de l'image.
> `100vw` = pleine largeur, `50vw` = demi-largeur (grille à 2 colonnes), etc.

### Vidéos : ajouter les sources WebM + utiliser .opt.mp4

**Avant :**
```html
<video src="video/Pinterest.mp4" muted playsinline loop preload="none"></video>
```

**Après :**
```html
<video muted playsinline loop preload="none"
       poster="video/Pinterest.poster.jpg">
  <source src="video/Pinterest.webm"    type="video/webm">
  <source src="video/Pinterest.opt.mp4" type="video/mp4">
</video>
```

Le navigateur prend WebM s'il sait (Chrome/Firefox/Edge), sinon le MP4
optimisé (Safari). L'original `Pinterest.mp4` reste sur disque, intact.

## 5) Vérifier le gain

Le script affiche un résumé à la fin :

```
Images processed : 73
Videos processed : 16
Bytes IN (originals, untouched) : 24.31 MB
Bytes OUT (new optimised files) : 7.82 MB
Net change vs originals         : -67.8%
```

## 6) Désinstaller / nettoyer

Pour repartir de zéro :

```powershell
Get-ChildItem -Path images,video,. -Recurse `
  -Include *.webp,*.avif,*.webm,*.opt.mp4,*.poster.jpg `
  | Remove-Item
```

(N'efface que les fichiers générés — jamais les originaux.)
