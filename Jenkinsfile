pipeline {
    agent any
    environment {
        VAULT_ADDR = 'http://jkt-vault1:8200'
        VAULT_TOKEN = credentials('vault-root-token')
    }
    stages {
        stage('1. Checkout from GitHub') {
            steps {
                checkout scm
            }
        }
        stage('2. Prepare & Execute Script') {
            steps {
                sh 'chmod +x hv_api2.sh'
                sh './hv_api.sh'
            }
        }
    }
}
