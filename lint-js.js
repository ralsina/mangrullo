#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

// Extract JavaScript from ECR template (all <script> blocks, joined)
function extractJavaScriptFromECR(filePath) {
    const content = fs.readFileSync(filePath, 'utf8');
    const blocks = [];
    const scriptRegex = /<script[^>]*>([\s\S]*?)<\/script>/g;
    let match;

    while ((match = scriptRegex.exec(content)) !== null) {
        blocks.push(match[1]);
    }

    if (blocks.length === 0) {
        return null;
    }
    return blocks.join('\n');
}

// Write extracted JavaScript to a temporary file
function lintECRJavaScript() {
    const templatePath = 'src/templates/dashboard.ecr';
    const tempJsPath = 'temp_dashboard.js';
    
    try {
        const jsContent = extractJavaScriptFromECR(templatePath);
        
        if (!jsContent) {
            console.log('No JavaScript found in template');
            return;
        }
        
        // Write to temp file
        fs.writeFileSync(tempJsPath, jsContent);
        
        // Run ESLint
        const { execSync } = require('child_process');
        try {
            const output = execSync(`npx eslint ${tempJsPath}`, { encoding: 'utf8' });
            console.log('✅ JavaScript linting passed');
        } catch (error) {
            console.log('❌ JavaScript linting errors found:');
            console.log(error.stdout);
            process.exit(1);
        }
    } catch (error) {
        console.error('Error:', error.message);
        process.exit(1);
    } finally {
        // Clean up temp file
        if (fs.existsSync(tempJsPath)) {
            fs.unlinkSync(tempJsPath);
        }
    }
}

if (require.main === module) {
    lintECRJavaScript();
}

module.exports = { extractJavaScriptFromECR, lintECRJavaScript };