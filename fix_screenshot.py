from PIL import Image, ImageDraw

img_path = '/Users/ameen/Downloads/Raw Screenshots/G.PNG'
img = Image.open(img_path).convert('RGB')
w, h = img.size

# Sample the background color slightly to the right of the center in the status bar
bg_color = img.getpixel((w//2, 80)) 
print("Detected bg color:", bg_color)

draw = ImageDraw.Draw(img)

# Paint over the "◀ Duo ABC" text below the time.
# Bounding box approximately: x from 0 to 400, y from 80 to 160.
draw.rectangle([0, 80, 450, 160], fill=bg_color)

out_path = '/Users/ameen/Downloads/Raw Screenshots/G.PNG' # Overwrite the original
img.save(out_path)
print("Saved and overwrote G.PNG")
