#!/bin/bash

# =============================================================
# Airflow on EC2 with Docker - Automated Setup Script
# Automates Phase 3 to Phase 6 from airflow_in_ec2.md
# Usage: chmod +x setup_airflow.sh && ./setup_airflow.sh
# =============================================================

set -e  # Exit immediately if any command fails

# ── Colors for output ──────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log()   { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ── Runtime Arguments ────────────────────────────────────
if [ -z "$1" ]; then
    error "S3 bucket name is required!\nUsage: ./setup_airflow.sh <s3-bucket-name> [aws-region]\nExample: ./setup_airflow.sh my-bucket ap-south-1"
fi

# ── Config ────────────────────────────────────────────────
S3_BUCKET="$1"                                    # ← from runtime argument
AWS_REGION="${2:-ap-south-1}"                     # ← optional, defaults to Mumbai
AIRFLOW_DIR="$HOME/airflow"

log "Using S3 Bucket : $S3_BUCKET"
log "Using AWS Region: $AWS_REGION"

# =============================================================
# PHASE 3 - Install Docker
# =============================================================
log "=========================================="
log "PHASE 3 - Installing Docker"
log "=========================================="

log "Updating system packages..."
sudo yum update -y

log "Installing Docker..."
sudo yum install docker -y

log "Starting and enabling Docker service..."
sudo systemctl start docker
sudo systemctl enable docker

log "Adding ec2-user to docker group..."
sudo usermod -aG docker ec2-user
sudo chmod 666 /var/run/docker.sock

log "Verifying Docker installation..."
docker --version || error "Docker installation failed!"

# =============================================================
# PHASE 3 - Install Docker Compose
# =============================================================
log "=========================================="
log "Installing Docker Compose"
log "=========================================="

log "Downloading Docker Compose..."
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
    -o /usr/local/bin/docker-compose

sudo chmod +x /usr/local/bin/docker-compose

log "Verifying Docker Compose installation..."
docker-compose --version || error "Docker Compose installation failed!"

# =============================================================
# PHASE 4 - Disk and Swap Setup
# =============================================================
log "=========================================="
log "PHASE 4 - Setting up Swap Memory"
log "=========================================="

if [ -f /swapfile ]; then
    warn "Swapfile already exists, skipping swap creation."
else
    log "Creating 2GB swap file..."
    sudo dd if=/dev/zero of=/swapfile bs=128M count=16
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    echo '/swapfile swap swap defaults 0 0' | sudo tee -a /etc/fstab
    log "Swap memory added successfully!"
fi

free -h

# =============================================================
# PHASE 5 - Setup Airflow
# =============================================================
log "=========================================="
log "PHASE 5 - Setting up Airflow"
log "=========================================="

log "Creating Airflow directory structure..."
mkdir -p $AIRFLOW_DIR/{dags,logs,plugins,config}
cd $AIRFLOW_DIR

log "Generating Fernet Key..."
FERNET_KEY=$(python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())")
log "Fernet Key generated successfully."

log "Creating .env file..."
cat > $AIRFLOW_DIR/.env << EOF
AIRFLOW_UID=$(id -u)
FERNET_KEY=${FERNET_KEY}
EOF
log ".env file created at $AIRFLOW_DIR/.env"

log "Downloading Airflow Docker Compose file..."
curl -LfO 'https://airflow.apache.org/docs/apache-airflow/stable/docker-compose.yaml'
log "docker-compose.yaml downloaded successfully."

log "Updating docker-compose.yaml with AWS provider..."
# Update only the first occurrence under x-airflow-common
sed -i '0,/_PIP_ADDITIONAL_REQUIREMENTS: ${_PIP_ADDITIONAL_REQUIREMENTS:-}/ s/_PIP_ADDITIONAL_REQUIREMENTS: ${_PIP_ADDITIONAL_REQUIREMENTS:-}/_PIP_ADDITIONAL_REQUIREMENTS: ${_PIP_ADDITIONAL_REQUIREMENTS:- apache-airflow-providers-amazon}/' \
    $AIRFLOW_DIR/docker-compose.yaml
log "docker-compose.yaml updated with amazon provider."

# =============================================================
# PHASE 6 - Start Airflow
# =============================================================
log "=========================================="
log "PHASE 6 - Starting Airflow"
log "=========================================="

cd $AIRFLOW_DIR

log "Initializing Airflow database (this may take 2-3 minutes)..."
docker-compose up airflow-init
log "Airflow database initialized successfully!"

log "Starting all Airflow services in background..."
docker-compose up -d

log "Waiting 60 seconds for all services to become healthy..."
sleep 60

log "Checking container status..."
docker-compose ps

# =============================================================
# PHASE 8 - Create Test S3 DAG
# =============================================================
log "=========================================="
log "Creating Test S3 DAG"
log "=========================================="

cat > $AIRFLOW_DIR/dags/test_s3.py << EOF
from airflow import DAG
from airflow.providers.amazon.aws.operators.s3 import S3ListOperator
from airflow.operators.python import PythonOperator
from datetime import datetime

with DAG(
    dag_id="test_s3_access",
    start_date=datetime(2024, 1, 1),
    schedule=None,
    catchup=False
) as dag:

    list_files = S3ListOperator(
        task_id="list_s3_files",
        bucket="${S3_BUCKET}",
        aws_conn_id="aws_default"
    )

    def print_files(**context):
        files = context['ti'].xcom_pull(task_ids='list_s3_files')
        print(f"Files in S3 bucket: {files}")

    print_files_task = PythonOperator(
        task_id="print_files",
        python_callable=print_files
    )

    list_files >> print_files_task
EOF

log "Test S3 DAG created at $AIRFLOW_DIR/dags/test_s3.py"

# =============================================================
# SETUP COMPLETE
# =============================================================
EC2_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  SETUP COMPLETE!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo -e "  Airflow UI  : ${YELLOW}http://${EC2_IP}:8080${NC}"
echo -e "  Username    : ${YELLOW}airflow${NC}"
echo -e "  Password    : ${YELLOW}airflow${NC}"
echo ""
echo -e "  Next Steps:"
echo -e "  1. Open browser → http://${EC2_IP}:8080"
echo -e "  2. Admin → Connections → Add aws_default connection"
echo -e "     Connection Type : Amazon Web Services"
echo -e "     Access Key      : (leave empty - IAM Role)"
echo -e "     Secret Key      : (leave empty - IAM Role)"
echo -e "     Extra           : {\"region_name\": \"${AWS_REGION}\"}"
echo -e "  3. Trigger test_s3_access DAG to verify S3 access"
echo ""
echo -e "${GREEN}============================================${NC}"
