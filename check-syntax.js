#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

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

// Check for syntax errors only
function checkJSSyntax() {
    const templatePath = 'src/templates/dashboard.ecr';
    const tempJsPath = 'temp_dashboard_syntax.js';
    
    try {
        const jsContent = extractJavaScriptFromECR(templatePath);
        
        if (!jsContent) {
            console.log('No JavaScript found in template');
            return;
        }
        
        // Write to temp file
        fs.writeFileSync(tempJsPath, jsContent);
        
        // Use Node.js to check syntax
        try {
            const output = execSync(`node -c ${tempJsPath}`, { encoding: 'utf8' });
            console.log('✅ JavaScript syntax is valid');
        } catch (error) {
            console.log('❌ JavaScript syntax error found:');
            // Try to get more detailed error info
            try {
                const testCode = `
                    try {
                        ${jsContent}
                    } catch (e) {
                        console.error('Syntax error:', e.message);
                        process.exit(1);
                    }
                    console.log('✅ JavaScript syntax is valid');
                `;
                fs.writeFileSync(tempJsPath, testCode);
                execSync(`node ${tempJsPath}`, { stdio: 'inherit' });
            } catch (e) {
                console.log('Could not determine exact error location');
            }
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
    checkJSSyntax();
}

module.exports = { extractJavaScriptFromECR, checkJSSyntax };