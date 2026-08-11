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

    - name: git
      image: alpine/git:latest
      command:
        - /bin/sh
      tty: true

  volumes:

    - name: docker-config
      emptyDir: {}
'''
            defaultContainer 'kaniko'
        }
    }


    stages {


        /*
         * ==========================================
         * STAGE 1 - BUILD & PUSH DOCKER IMAGE
         * ==========================================
         */

        stage('Build Docker Image') {

            steps {

                container('kaniko') {

                    withCredentials([
                        usernamePassword(
                            credentialsId: 'dockerhub-creds',
                            usernameVariable: 'DOCKER_USERNAME',
                            passwordVariable: 'DOCKER_PASSWORD'
                        )
                    ]) {

                        sh '''
                            set -e

                            echo "=========================================="
                            echo "Creating Docker Hub authentication"
                            echo "=========================================="

                            mkdir -p /kaniko/.docker

                            AUTH=$(printf "%s:%s" \
                              "$DOCKER_USERNAME" \
                              "$DOCKER_PASSWORD" \
                              | base64 \
                              | tr -d '\\n')

                            cat > /kaniko/.docker/config.json <<EOF
{
  "auths": {
    "https://index.docker.io/v1/": {
      "auth": "$AUTH"
    }
  }
}
EOF

                            echo "=========================================="
                            echo "Starting Kaniko Docker build"
                            echo "=========================================="

                            /kaniko/executor \
                              --context="$WORKSPACE" \
                              --dockerfile="$WORKSPACE/Dockerfile" \
                              --destination="docker.io/$DOCKER_USERNAME/postgres-rag:$BUILD_NUMBER"

                            echo "=========================================="
                            echo "Docker image pushed successfully"
                            echo "=========================================="

                            echo "Image:"
                            echo "docker.io/$DOCKER_USERNAME/postgres-rag:$BUILD_NUMBER"
                        '''
                    }
                }
            }
        }


        /*
         * ==========================================
         * STAGE 2 - UPDATE GITOPS REPOSITORY
         * ==========================================
         */

        stage('Update GitOps Manifest') {

            steps {

                container('git') {

                    withCredentials([
                        usernamePassword(
                            credentialsId: 'github-creds',
                            usernameVariable: 'GIT_USERNAME',
                            passwordVariable: 'GIT_TOKEN'
                        )
                    ]) {

                        sh '''
                            set -e

                            echo "=========================================="
                            echo "Cloning GitOps repository"
                            echo "=========================================="

                            rm -rf postgres-rag-gitops

                            git clone \
                              https://$GIT_USERNAME:$GIT_TOKEN@github.com/muskan7860/postgres-rag-gitops.git \
                              postgres-rag-gitops

                            cd postgres-rag-gitops

                            echo "=========================================="
                            echo "Current Kubernetes image"
                            echo "=========================================="

                            grep "image:" k8s/deployment.yml || true

                            echo "=========================================="
                            echo "Updating image tag"
                            echo "=========================================="

                            sed -i \
                              "s|image:.*postgres-rag:.*|image: docker.io/muskanpatel71198/postgres-rag:$BUILD_NUMBER|g" \
                              k8s/deployment.yml

                            echo "=========================================="
                            echo "Updated Kubernetes image"
                            echo "=========================================="

                            grep "image:" k8s/deployment.yml

                            echo "=========================================="
                            echo "Git status"
                            echo "=========================================="

                            git status

                            git config user.name "Jenkins CI"
                            git config user.email "jenkins@localhost"

                            git add k8s/deployment.yml

                            git commit \
                              -m "Update postgres-rag image to build $BUILD_NUMBER" \
                              || echo "No changes to commit"

                            git push origin main

                            echo "=========================================="
                            echo "GitOps repository updated successfully"
                            echo "=========================================="
                        '''
                    }
                }
            }
        }
    }


    /*
     * ==========================================
     * POST ACTIONS
     * ==========================================
     */

    post {

        success {

            echo '''
==========================================
CI PIPELINE SUCCESS
==========================================

Docker image built and pushed.

GitOps deployment manifest updated.

Argo CD will detect the GitOps change
and synchronize the application to Kubernetes.

==========================================
'''
        }

        failure {

            echo '''
==========================================
CI PIPELINE FAILED
==========================================

Check the Jenkins console output.

==========================================
'''
        }
    }
}
