#!/usr/bin/env node
// generate_icons.js
//
// Génère des icônes placeholder StreetPhare pour Android (mipmap) et Windows (ICO).
// Remplacez assets/icon/streetphare_icon.png par le vrai logo avant exécution.
//
// Usage : node generate_icons.js
// Puis   : flutter pub run flutter_launcher_icons

'use strict';
const fs = require('fs');
const path = require('path');

// ── SVG minimal StreetPhare (lampe) ──────────────────────────────────────────
// Simple icône vectorielle : un disque foncé avec une flèche/lampe jaune.
function streetphareSvg(size) {
  const r = size / 2;
  const lampR = size * 0.28;
  const baseY = size * 0.72;
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}">
  <rect width="${size}" height="${size}" rx="${size * 0.18}" fill="#0d1117"/>
  <circle cx="${r}" cy="${r * 0.82}" r="${lampR}" fill="#FFB300" opacity="0.95"/>
  <polygon points="${r},${r * 0.28} ${r - lampR * 0.7},${r * 1.05} ${r + lampR * 0.7},${r * 1.05}" fill="#FFD54F" opacity="0.6"/>
  <rect x="${r - size * 0.04}" y="${baseY}" width="${size * 0.08}" height="${size * 0.12}" rx="2" fill="#8b949e"/>
  <text x="${r}" y="${size * 0.96}" text-anchor="middle" font-size="${size * 0.1}" fill="#c9d1d9" font-family="Arial,sans-serif" font-weight="bold">SP</text>
</svg>`;
}

// ── Conversion SVG → PNG approximée (via Data URI, sans dépendance) ─────────
// On crée directement un PNG 1-canal minimal (fallback si canvas non dispo).
function createMinimalPng(size) {
  // PNG 8x8 avec un cercle jaune sur fond sombre (placeholder minimal).
  // Pour de vraies icônes, utiliser sharp ou canvas.
  const width = size;
  const height = size;

  // PNG header
  const signature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  
  // IHDR
  const ihdrData = Buffer.alloc(13);
  ihdrData.writeUInt32BE(width, 0);
  ihdrData.writeUInt32BE(height, 4);
  ihdrData[8] = 8; // bit depth
  ihdrData[9] = 2; // color type: RGB
  ihdrData[10] = 0; ihdrData[11] = 0; ihdrData[12] = 0;
  
  function crc32(buf) {
    let c = 0xFFFFFFFF;
    const table = new Int32Array(256);
    for (let n = 0; n < 256; n++) {
      let v = n;
      for (let k = 0; k < 8; k++) v = v & 1 ? 0xEDB88320 ^ (v >>> 1) : v >>> 1;
      table[n] = v;
    }
    for (let i = 0; i < buf.length; i++) c = table[(c ^ buf[i]) & 0xFF] ^ (c >>> 8);
    return (c ^ 0xFFFFFFFF) >>> 0;
  }

  function chunk(type, data) {
    const len = Buffer.alloc(4);
    len.writeUInt32BE(data.length, 0);
    const typeData = Buffer.concat([Buffer.from(type), data]);
    const crc = Buffer.alloc(4);
    crc.writeUInt32BE(crc32(typeData), 0);
    return Buffer.concat([len, typeData, crc]);
  }

  // Raw image data (RGB, no filter)
  const rawData = Buffer.alloc((width * 3 + 1) * height);
  const cx = width / 2;
  const cy = height * 0.45;
  const radius = width * 0.28;

  for (let y = 0; y < height; y++) {
    const rowOffset = y * (width * 3 + 1);
    rawData[rowOffset] = 0; // filter: none
    for (let x = 0; x < width; x++) {
      const px = rowOffset + 1 + x * 3;
      const dx = x - cx;
      const dy = y - cy;
      const dist = Math.sqrt(dx * dx + dy * dy);
      
      // Fond sombre
      let r = 0x0d, g = 0x11, b = 0x17;
      
      // Cercle principal (coin arrondi)
      if (y < height * 0.88 && y > height * 0.08) {
        // Background card
        const cornerR = width * 0.15;
        const inCard = (
          (y > cornerR && y < height - cornerR) ||
          (x > cornerR && x < width - cornerR) ||
          (Math.sqrt(Math.max(0, (y < cornerR ? y - cornerR : y - height + cornerR) ** 2 + 
                      (x < cornerR ? x - cornerR : x - width + cornerR) ** 2)) < cornerR)
        );
        if (inCard) { r = 0x16; g = 0x1b; b = 0x22; }
      }
      
      // Lampe jaune (cercle)
      if (dist < radius) {
        r = 0xFF; g = 0xB3; b = 0x00;
      }
      // Halo externe
      if (dist >= radius && dist < radius * 1.3) {
        const alpha = 1 - (dist - radius) / (radius * 0.3);
        r = Math.round(r + (0xFF - r) * alpha * 0.3);
        g = Math.round(g + (0xD5 - g) * alpha * 0.3);
        b = Math.round(b + (0x4F - b) * alpha * 0.3);
      }
      
      // Triangle de lumière (dessous de la lampe)
      const triCenter = cy + radius * 1.2;
      const triWidth = radius * 0.8;
      const triHeight = radius * 1.0;
      if (y > cy + radius * 0.5 && y < cy + radius * 1.5) {
        const progress = (y - (cy + radius * 0.5)) / triHeight;
        const localWidth = triWidth * (1 - progress * 0.3);
        if (Math.abs(x - cx) < localWidth) {
          const tAlpha = 0.4 * (1 - progress);
          r = Math.round(r + (0xFF - r) * tAlpha);
          g = Math.round(g + (0xD5 - g) * tAlpha);
          b = Math.round(b + (0x4F - b) * tAlpha);
        }
      }

      rawData[px] = r;
      rawData[px + 1] = g;
      rawData[px + 2] = b;
    }
  }

  // Compress with zlib
  const zlib = require('zlib');
  const compressed = zlib.deflateSync(rawData);

  const ihdr = chunk('IHDR', ihdrData);
  const idat = chunk('IDAT', compressed);
  const iend = chunk('IEND', Buffer.alloc(0));

  return Buffer.concat([signature, ihdr, idat, iend]);
}

// ── Main ─────────────────────────────────────────────────────────────────────
function main() {
  const assetsDir = path.join(__dirname, 'assets', 'icon');
  const androidDir = path.join(__dirname, 'android', 'app', 'src', 'main', 'res');
  
  // Crée le dossier assets/icon s'il n'existe pas
  if (!fs.existsSync(assetsDir)) {
    fs.mkdirSync(assetsDir, { recursive: true });
  }

  // Génère le PNG placeholder principal
  const mainPng = createMinimalPng(1024);
  const mainPath = path.join(assetsDir, 'streetphare_icon.png');
  fs.writeFileSync(mainPath, mainPng);
  console.log(`✅ Icône principale générée : ${mainPath} (1024x1024)`);

  // Génère les tailles Android mipmap
  const mipmapSizes = {
    'mipmap-mdpi': 48,
    'mipmap-hdpi': 72,
    'mipmap-xhdpi': 96,
    'mipmap-xxhdpi': 144,
    'mipmap-xxxhdpi': 192,
  };

  for (const [folder, size] of Object.entries(mipmapSizes)) {
    const dir = path.join(androidDir, folder);
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }
    const png = createMinimalPng(size);
    const outPath = path.join(dir, 'ic_launcher.png');
    fs.writeFileSync(outPath, png);
    console.log(`✅ ${folder}/ic_launcher.png (${size}x${size})`);
  }

  // Windows ICO (multi-size)
  const icoSizes = [16, 32, 48, 64, 128, 256];
  const icoImages = icoSizes.map(s => {
    const png = createMinimalPng(s);
    return { size: s, data: png };
  });

  // ICO format
  const icoHeader = Buffer.alloc(6);
  icoHeader.writeUInt16LE(0, 0);      // reserved
  icoHeader.writeUInt16LE(1, 2);      // type: ICO
  icoHeader.writeUInt16LE(icoImages.length, 4); // count

  let dataOffset = 6 + (icoImages.length * 16);
  const entries = [];
  const imageData = [];

  for (const img of icoImages) {
    const entry = Buffer.alloc(16);
    entry[0] = img.size >= 256 ? 0 : img.size;
    entry[1] = img.size >= 256 ? 0 : img.size;
    entry[2] = 0;  // color count
    entry[3] = 0;  // reserved
    entry.writeUInt16LE(1, 4);  // planes
    entry.writeUInt16LE(24, 6); // bits per pixel
    entry.writeUInt32LE(img.data.length, 8);  // size
    entry.writeUInt32LE(dataOffset, 12);      // offset
    entries.push(entry);
    imageData.push(img.data);
    dataOffset += img.data.length;
  }

  const windowsDir = path.join(__dirname, 'windows', 'runner', 'resources');
  if (!fs.existsSync(windowsDir)) {
    fs.mkdirSync(windowsDir, { recursive: true });
  }
  const icoPath = path.join(windowsDir, 'app_icon.ico');
  fs.writeFileSync(icoPath, Buffer.concat([icoHeader, ...entries, ...imageData]));
  console.log(`✅ ${icoPath} (ICO multi-size: ${icoSizes.join(', ')})`);

  // Copie aussi dans assets/icon pour flutter_launcher_icons
  fs.writeFileSync(path.join(assetsDir, 'streetphare_icon.ico'), 
    Buffer.concat([icoHeader, ...entries, ...imageData]));
  console.log(`✅ assets/icon/streetphare_icon.ico`);

  console.log('\n🎉 Toutes les icônes générées !');
  console.log('\nProchaines étapes :');
  console.log('  1. Remplacez assets/icon/streetphare_icon.png par le vrai logo StreetPhare');
  console.log('  2. Exécutez : flutter pub add flutter_launcher_icons');
  console.log('  3. Puis     : flutter pub run flutter_launcher_icons');
}

main();