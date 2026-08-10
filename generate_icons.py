from PIL import Image, ImageDraw, ImageFont
import os

# Create icon sizes
sizes = [
    (1024, 1024, 'icon_1024.png'),
    (512, 512, 'icon_512.png'),
    (256, 256, 'icon_256.png'),
    (180, 180, 'icon_180.png'),
    (128, 128, 'icon_128.png'),
    (96, 96, 'icon_96.png'),
    (72, 72, 'icon_72.png'),
    (48, 48, 'icon_48.png'),
    (32, 32, 'icon_32.png'),
]

icon_dir = '/home/yuki/Documents/Celsuis/celsuis/assets/icons'

for width, height, filename in sizes:
    img = Image.new('RGBA', (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    # Draw red rounded rectangle background (Apple Music style)
    margin = int(width * 0.12)
    draw.rounded_rectangle(
        [margin, margin, width - margin, height - margin],
        radius=int(width * 0.22),
        fill='#DC2626'
    )
    
    # Draw white music note (♪)
    try:
        font_size = int(width * 0.55)
        font = ImageFont.truetype('/usr/share/fonts/google-noto-vf/NotoColorEmoji.ttf', font_size)
    except:
        try:
            font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', font_size)
        except:
            font = ImageFont.load_default()
    
    # Center the music note
    bbox = draw.textbbox((0, 0), '♪', font=font)
    text_width = bbox[2] - bbox[0]
    text_height = bbox[3] - bbox[1]
    x = (width - text_width) / 2 - bbox[0]
    y = (height - text_height) / 2 - bbox[1]
    
    draw.text((x, y), '♪', fill='#FFFFFF', font=font)
    
    img.save(os.path.join(icon_dir, filename))
    print(f'Created {filename}')

# Create splash screen assets
splash_dir = os.path.join(icon_dir, 'splash')
os.makedirs(splash_dir, exist_ok=True)

for size_name, dim in [('ldpi', (144, 144)), ('mdpi', (192, 192)), ('hdpi', (288, 288)), ('xhdpi', (384, 384)), ('xxhdpi', (576, 576)), ('xxxhdpi', (768, 768))]:
    img = Image.new('RGBA', (dim[0], dim[1]), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    # Red background
    draw.rounded_rectangle(
        [0, 0, dim[0], dim[1]],
        radius=0,
        fill='#DC2626'
    )
    
    # White circle with music note
    center = dim[0] / 2
    circle_radius = dim[0] * 0.3
    draw.ellipse([center - circle_radius, center - circle_radius, center + circle_radius, center + circle_radius], fill='#FFFFFF')
    
    try:
        font_size = int(dim[0] * 0.3)
        font = ImageFont.truetype('/usr/share/fonts/google-noto-vf/NotoColorEmoji.ttf', font_size)
    except:
        try:
            font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', font_size)
        except:
            font = ImageFont.load_default()
    
    draw.text((center - 20, center - 20), '♪', fill='#DC2626', font=font)
    
    img.save(os.path.join(splash_dir, f'splash_{size_name}.png'))
    print(f'Created splash_{size_name}.png')

print('All icons created!')
