import os
from PIL import Image, ImageDraw, ImageFont

def draw_logo(size=512):
    scale = 4
    w, h = size * scale, size * scale
    img = Image.new('RGBA', (w, h), (0, 0, 0, 255))
    draw = ImageDraw.Draw(img)
    
    center_x = w // 2
    center_y = int(h * 0.38) # y = 194.5 * scale
    
    # Outer circle (diameter 240 -> radius 120)
    r1 = int(120 * scale)
    t1 = int(16 * scale)
    draw.ellipse([center_x - r1, center_y - r1, center_x + r1, center_y + r1], outline=(255, 255, 255, 255), width=t1)
    
    # Inner circle (diameter 144 -> radius 72)
    r2 = int(72 * scale)
    draw.ellipse([center_x - r2, center_y - r2, center_x + r2, center_y + r2], outline=(255, 255, 255, 255), width=t1)
    
    # Center core square (28x28)
    sq = int(14 * scale)
    draw.rectangle([center_x - sq, center_y - sq, center_x + sq, center_y + sq], fill=(255, 255, 255, 255))
    
    # Text SYNC
    try:
        font_size = int(68 * scale)
        font = ImageFont.truetype("arial.ttf", font_size)
    except Exception:
        font = ImageFont.load_default()
        
    text = "SYNC"
    bbox = draw.textbbox((0, 0), text, font=font)
    text_w = bbox[2] - bbox[0]
    text_y = int(h * 0.72)
    
    draw.text((center_x - (text_w // 2), text_y), text, fill=(255, 255, 255, 255), font=font)
    
    # Accent rule under text
    rule_w = int(120 * scale)
    rule_h = int(3 * scale)
    rule_y = text_y + int(86 * scale)
    draw.rectangle([center_x - rule_w // 2, rule_y, center_x + rule_w // 2, rule_y + rule_h], fill=(255, 255, 255, 255))
    
    return img.resize((size, size), Image.Resampling.LANCZOS)

def draw_og_image(width=1280, height=640):
    scale = 2
    w, h = width * scale, height * scale
    img = Image.new('RGBA', (w, h), (0, 0, 0, 255))
    draw = ImageDraw.Draw(img)
    
    # Left logo center at x = 320 (in 1280 space), y = 220
    cx = int(320 * scale)
    cy = int(220 * scale)
    
    r1 = int(100 * scale)
    t1 = int(12 * scale)
    draw.ellipse([cx - r1, cy - r1, cx + r1, cy + r1], outline=(255, 255, 255, 255), width=t1)
    
    r2 = int(60 * scale)
    draw.ellipse([cx - r2, cy - r2, cx + r2, cy + r2], outline=(255, 255, 255, 255), width=t1)
    
    sq = int(12 * scale)
    draw.rectangle([cx - sq, cy - sq, cx + sq, cy + sq], fill=(255, 255, 255, 255))
    
    try:
        font_brand = ImageFont.truetype("arial.ttf", int(56 * scale))
        font_mono = ImageFont.truetype("consola.ttf", int(20 * scale))
        font_sub = ImageFont.truetype("consola.ttf", int(16 * scale))
    except Exception:
        font_brand = font_mono = font_sub = ImageFont.load_default()
        
    text = "SYNC"
    bbox = draw.textbbox((0, 0), text, font=font_brand)
    text_w = bbox[2] - bbox[0]
    draw.text((cx - (text_w // 2), cy + r1 + int(24 * scale)), text, fill=(255, 255, 255, 255), font=font_brand)
    
    # Accent line under SYNC text on left
    draw.rectangle([cx - int(50 * scale), cy + r1 + int(96 * scale), cx + int(50 * scale), cy + r1 + int(98 * scale)], fill=(255, 255, 255, 255))
    
    # Right side text block starting at x = 620
    rx = int(620 * scale)
    ry = int(160 * scale)
    
    lines = [
        ("WAKE / PAIR / GET OUT OF BED", 255),
        ("REALTIME ACROSS TWO PHONES", 215),
        ("ONE INVITE CODE. NO ACCOUNTS TO FORGET.", 215),
        ("OPEN SOURCE. ANDROID + iOS.", 215),
        ("v1.0.0 · brutalist-monochrome", 150),
    ]
    
    step = int(42 * scale)
    for i, (line, opac) in enumerate(lines):
        draw.text((rx, ry + i * step), line, fill=(255, 255, 255, opac), font=font_mono)
        
    # Footer line & repo text at y = 520
    fy = int(520 * scale)
    draw.rectangle([int(160 * scale), fy, int(1120 * scale), fy + int(2 * scale)], fill=(255, 255, 255, 100))
    draw.text((int(160 * scale), fy + int(20 * scale)), "github.com/Cyrusbye720/sync", fill=(255, 255, 255, 150), font=font_sub)
    
    return img.resize((width, height), Image.Resampling.LANCZOS)

if __name__ == '__main__':
    os.makedirs('assets', exist_ok=True)
    draw_logo(512).save('assets/logo.png')
    draw_og_image(1280, 640).save('assets/og-image.png')
    print("Regenerated clean logo.png and og-image.png")
