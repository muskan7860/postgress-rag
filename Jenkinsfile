pipeline {

    agent {
        kubernetes {
            yaml '''
apiVersion: v1
kind: Pod
spec:
  hostNetwork: true
  dnsPolicy: Default

  containers:
    - name: kaniko
      image: gcr.io/kaniko-project/executor:v1.23.2-debug
      command:
        - /busybox/cat
      tty: true
      volumeMounts:
        - name: docker-config
          mountPath: /kaniko/.docker

  volumes:
    - name: docker-config
      emptyDir: {}
'''
            defaultContainer 'kaniko'
        }
    }

    stages {

        stage('Build Docker Image') {
            steps {

                withCredentials([
                    usernamePassword(
                        credentialsId: 'dockerhub-creds',
                        usernameVariable: 'DOCKER_USERNAME',
                        passwordVariable: 'DOCKER_PASSWORD'
                    )
                ]) {

                    sh '''
                        set -e

                        mkdir -p /kaniko/.docker

                        AUTH=$(printf "%s:%s" "$DOCKER_USERNAME" "$DOCKER_PASSWORD" | base64 | tr -d '\\n')

                        cat > /kaniko/.docker/config.json <<EOF
{
  "auths": {
    "https://index.docker.io/v1/": {
      "auth": "$AUTH"
    }
  }
}
EOF

                        echo "Starting Kaniko build..."

                        /kaniko/executor \
                          --context="$WORKSPACE" \
                          --dockerfile="$WORKSPACE/Dockerfile" \
                          --destination="docker.io/$DOCKER_USERNAME/postgres-rag:$BUILD_NUMBER"

                        echo "Docker image pushed successfully."
                    '''
                }
            }
        }
    }
}