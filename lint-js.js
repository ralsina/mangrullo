#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

// Extract JavaScript from ECR template
function extractJavaScriptFromECR(filePath) {
    const content = fs.readFileSync(filePath, 'utf8');
    const jsMatch = content.match(/<script[^>]*>([\s\S]*?)<\/script>/);
    
    if (jsMatch) {
        return jsMatch[1];
    }
    return null;
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