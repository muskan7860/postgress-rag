pipeline {

    agent {
        kubernetes {
            yaml '''
apiVersion: v1
kind: Pod
spec:
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

    environment {

        IMAGE_NAME = 'docker.io/muskanpatel71198/postgres-rag'

        GITOPS_REPO = 'https://github.com/muskan7860/postgres-rag-gitops.git'

        IMAGE_TAG = "${BUILD_NUMBER}"
    }

    stages {

        stage('Checkout Application') {

            steps {

                checkout scm

                sh '''
                    echo "========================================"
                    echo "Application source checked out"
                    echo "========================================"

                    echo "Workspace:"
                    echo "$WORKSPACE"

                    ls -la
                '''
            }
        }

        stage('Build & Push Docker Image') {

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

                        echo "========================================"
                        echo "Building Docker Image"
                        echo "========================================"

                        echo "Image:"
                        echo "$IMAGE_NAME:$IMAGE_TAG"

                        mkdir -p /kaniko/.docker

                        AUTH=$(printf "%s:%s" \
                          "$DOCKER_USERNAME" \
                          "$DOCKER_PASSWORD" | \
                          base64 | tr -d '\\n')

                        cat > /kaniko/.docker/config.json <<EOF
{
  "auths": {
    "https://index.docker.io/v1/": {
      "auth": "$AUTH"
    }
  }
}
EOF

                        /kaniko/executor \
                          --context="$WORKSPACE" \
                          --dockerfile="$WORKSPACE/Dockerfile" \
                          --destination="$IMAGE_NAME:$IMAGE_TAG"

                        echo "========================================"
                        echo "Docker image pushed successfully"
                        echo "========================================"

                        echo "$IMAGE_NAME:$IMAGE_TAG"
                    '''
                }
            }
        }

        stage('Update GitOps Repository') {

            steps {

                withCredentials([
                    usernamePassword(
                        credentialsId: 'github-creds',
                        usernameVariable: 'GIT_USERNAME',
                        passwordVariable: 'GIT_PASSWORD'
                    )
                ]) {

                    sh '''
                        set -e

                        echo "========================================"
                        echo "Cloning GitOps repository"
                        echo "========================================"

                        rm -rf gitops

                        git clone \
                          https://${GIT_USERNAME}:${GIT_PASSWORD}@github.com/muskan7860/postgres-rag-gitops.git \
                          gitops

                        cd gitops

                        echo "Current image:"
                        grep "image:" k8s/deployment.yml

                        echo "Updating image tag:"
                        echo "$IMAGE_TAG"

                        sed -i \
                          "s|image: docker.io/muskanpatel71198/postgres-rag:.*|image: docker.io/muskanpatel71198/postgres-rag:${IMAGE_TAG}|" \
                          k8s/deployment.yml

                        echo "Updated image:"
                        grep "image:" k8s/deployment.yml
                    '''
                }
            }
        }

        stage('Commit & Push GitOps Change') {

            steps {

                withCredentials([
                    usernamePassword(
                        credentialsId: 'github-creds',
                        usernameVariable: 'GIT_USERNAME',
                        passwordVariable: 'GIT_PASSWORD'
                    )
                ]) {

                    sh '''
                        set -e

                        cd gitops

                        git config user.name "Jenkins"
                        git config user.email "jenkins@localhost"

                        git add k8s/deployment.yml

                        git commit \
                          -m "Update postgres-rag image to ${IMAGE_TAG}" \
                          || echo "No changes to commit."

                        git push \
                          https://${GIT_USERNAME}:${GIT_PASSWORD}@github.com/muskan7860/postgres-rag-gitops.git \
                          HEAD:main

                        echo "========================================"
                        echo "GitOps repository updated successfully"
                        echo "========================================"

                        echo "Image tag:"
                        echo "$IMAGE_TAG"
                    '''
                }
            }
        }
    }

    post {

        success {

            echo """
========================================
PIPELINE SUCCESS
========================================

Docker Image:
$IMAGE_NAME:$IMAGE_TAG

GitOps Repository:
$GITOPS_REPO

Argo CD:
Will detect the Git change

MicroK8s:
Argo CD will synchronize the application

========================================
"""
        }

        failure {

            echo """
========================================
PIPELINE FAILED
========================================

Check the Jenkins stage logs.

========================================
"""
        }
    }
}
