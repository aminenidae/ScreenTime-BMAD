import os
import subprocess
import json

def resize_image(input_path, output_path, width, height):
    try:
        subprocess.run(['sips', '-z', str(height), str(width), input_path, '--out', output_path], check=True, stdout=subprocess.DEVNULL)
        return True
    except subprocess.CalledProcessError:
        print(f"Failed to resize {input_path} to {output_path}")
        return False

def generate_icons():
    base_dir = "/Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/Assets.xcassets/AppIcon.appiconset"
    master_icon = os.path.join(base_dir, "AppIcon.png")
    
    if not os.path.exists(master_icon):
        print(f"Error: Master icon not found at {master_icon}")
        return

    # resize master to 1024x1024 first to fix warning
    resize_image(master_icon, master_icon, 1024, 1024)

    images = []
    
    # Define configurations (filename_suffix, size_pt, scale, idiom)
    configs = [
        # iPhone
        ("20x20@2x", 20, 2, "iphone"),
        ("20x20@3x", 20, 3, "iphone"),
        ("29x29@2x", 29, 2, "iphone"),
        ("29x29@3x", 29, 3, "iphone"),
        ("40x40@2x", 40, 2, "iphone"),
        ("40x40@3x", 40, 3, "iphone"),
        ("60x60@2x", 60, 2, "iphone"),
        ("60x60@3x", 60, 3, "iphone"),
        
        # iPad
        ("20x20~ipad", 20, 1, "ipad"),
        ("20x20@2x~ipad", 20, 2, "ipad"),
        ("29x29~ipad", 29, 1, "ipad"),
        ("29x29@2x~ipad", 29, 2, "ipad"),
        ("40x40~ipad", 40, 1, "ipad"),
        ("40x40@2x~ipad", 40, 2, "ipad"),
        ("76x76~ipad", 76, 1, "ipad"),
        ("76x76@2x~ipad", 76, 2, "ipad"),
        ("83.5x83.5@2x~ipad", 83.5, 2, "ipad"),
        
        # Marketing
        ("1024x1024", 1024, 1, "ios-marketing")
    ]

    json_images = []

    for suffix, size_pt, scale, idiom in configs:
        filename = f"Icon-{suffix}.png"
        output_path = os.path.join(base_dir, filename)
        
        # Calculate pixel dimensions
        px = int(size_pt * scale)
        
        if resize_image(master_icon, output_path, px, px):
            entry = {
                "size": f"{size_pt}x{size_pt}" if size_pt != 83.5 else "83.5x83.5",
                "idiom": idiom,
                "filename": filename,
                "scale": f"{scale}x"
            }
            json_images.append(entry)

    contents = {
        "images": json_images,
        "info": {
            "version": 1,
            "author": "xcode"
        }
    }

    with open(os.path.join(base_dir, "Contents.json"), "w") as f:
        json.dump(contents, f, indent=2)
    
    print("Successfully generated icons and Contents.json")

if __name__ == "__main__":
    generate_icons()
