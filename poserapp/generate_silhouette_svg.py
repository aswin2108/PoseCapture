import cv2
import numpy as np
import argparse
import os

try:
    from rembg import remove
    from PIL import Image
except ImportError:
    print("Missing dependencies. Please run: pip install rembg opencv-python pillow")
    exit(1)

def generate_svg_from_image(image_path, output_path, simplify_tolerance=2.0, padding=10):
    """
    Reads an image, removes background, extracts contour, and saves as an SVG.
    """
    print(f"Processing: {image_path}")
    
    if not os.path.exists(image_path):
        print(f"Error: File {image_path} does not exist.")
        return

    # 1. Read image with PIL
    input_image = Image.open(image_path)
    
    # 2. Remove background using rembg
    print("Removing background (this may take a moment to download the model on first run)...")
    output_image = remove(input_image)
    
    # 3. Convert PIL image to OpenCV format (numpy array)
    open_cv_image = np.array(output_image)
    
    # 4. Extract alpha channel as mask
    # rembg returns an RGBA image. The alpha channel is at index 3.
    if open_cv_image.shape[2] != 4:
        print("Error: Expected RGBA image from rembg.")
        return
        
    alpha_mask = open_cv_image[:, :, 3]
    
    # Threshold just to be safe
    _, binary_mask = cv2.threshold(alpha_mask, 127, 255, cv2.THRESH_BINARY)
    
    # 5. Find contours on the binary mask
    # RETR_EXTERNAL gets only the outermost contour (the silhouette)
    contours, _ = cv2.findContours(binary_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    
    if not contours:
        print("No contours found in the image!")
        return
        
    # Get the largest contour (assuming the person is the largest object)
    largest_contour = max(contours, key=cv2.contourArea)
    
    # 6. Simplify the contour to make the SVG smaller and smoother
    # The tolerance parameter controls how aggressive the simplification is.
    epsilon = simplify_tolerance * cv2.arcLength(largest_contour, True) / 1000.0
    simplified_contour = cv2.approxPolyDP(largest_contour, epsilon, True)
    
    # 7. Generate SVG path
    path_data = []
    for i, point in enumerate(simplified_contour):
        x, y = point[0]
        if i == 0:
            path_data.append(f"M {x},{y}")
        else:
            path_data.append(f"L {x},{y}")
    
    path_data.append("Z") # Close the path
    svg_path = " ".join(path_data)
    
    # 8. Create SVG file content
    h, w = binary_mask.shape
    svg_content = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="-{padding} -{padding} {w + padding*2} {h + padding*2}">
    <path d="{svg_path}" fill="none" stroke="white" stroke-width="3" stroke-linejoin="round"/>
</svg>'''
    
    # Optional: We can also print the raw JSON format for PoserApp
    json_format = f'''
{{
  "id": "{os.path.splitext(os.path.basename(image_path))[0]}",
  "name": "Custom Pose",
  "category": "custom",
  "svg_path": "{svg_path}",
  "svg_viewbox": "0 0 {w} {h}",
  "landmarks": {{}}
}}
'''
    
    # Write the raw SVG file
    with open(output_path, "w") as f:
        f.write(svg_content)
        
    # Write the JSON file for the app
    json_output_path = os.path.splitext(output_path)[0] + ".json"
    with open(json_output_path, "w") as f:
        f.write(json_format.strip())
        
    print(f"Successfully created SVG: {output_path}")
    print(f"Successfully created App JSON: {json_output_path}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Convert a photo to a silhouette SVG for PoserApp")
    parser.add_argument("input_image", help="Path to the input reference photo")
    parser.add_argument("output_svg", help="Path to save the output SVG file")
    parser.add_argument("--tolerance", type=float, default=1.5, help="Contour simplification tolerance (higher = fewer points, default=1.5)")
    
    args = parser.parse_args()
    
    generate_svg_from_image(args.input_image, args.output_svg, args.tolerance)
