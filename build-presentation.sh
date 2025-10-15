#!/bin/bash

echo "🎨 Building presentation with Marp..."

# Create output directory
mkdir -p output

# Build PDF
echo "📄 Generating PDF..."
marp presentation.md --pdf --allow-local-files -o output/presentation.pdf

# Build HTML
echo "🌐 Generating HTML..."
marp presentation.md --html --allow-local-files -o output/presentation.html

# Build PowerPoint
echo "📊 Generating PowerPoint..."
marp presentation.md --pptx --allow-local-files -o output/presentation.pptx

echo "✅ Presentation built successfully!"
echo "📁 Output files:"
ls -la output/

echo ""
echo "🚀 To serve the presentation locally:"
echo "   marp presentation.md --server --allow-local-files --port 8080"