# Apache Airflow on EC2 with Docker - Complete Working Guide
### S3 Access via IAM Role (No Credentials Needed)
---

## Setup Summary
```
EC2 Instance  : m7i-flex.large (2 vCPU, 8 GB RAM)
OS            : Amazon Linux 2023
Storage       : 20 GB EBS
Airflow       : 3.2.0 (via Docker)
Access to S3  : IAM Role (no access keys)
```

---

## Phase 1 - AWS Setup (Before Touching EC2)

### Step 1 - Create IAM Role
```
AWS Console
      ↓
IAM → Roles → Create Role
      ↓
Trusted Entity: AWS Service → EC2
      ↓
Attach Policy: AmazonS3FullAccess
      ↓
Role Name: airflow-ec2-role
      ↓
Create Role
```

### Step 2 - Launch EC2 Instance
```
AWS Console → EC2 → Launch Instance
      ↓
AMI           : Amazon Linux 2023
Instance Type : m7i-flex.large (2 vCPU, 8 GB RAM)
Key Pair      : Create or use existing (.ppk for Putty)
Storage       : 20 GB EBS
      ↓
Advanced Details → IAM Instance Profile
→ Select: airflow-ec2-role
      ↓
Security Group Inbound Rules:
├── SSH        : Port 22         → Your IP
└── Custom TCP : Port 8080       → Your IP   ← IMPORTANT: Use "Custom TCP" not "HTTP"
      ↓
Launch
```

> **Note:** When adding port 8080, select **Custom TCP** (not HTTP).
> HTTP locks port to 80 and disables editing.

---

## Phase 2 - Connect to EC2

### Step 3 - Connect via Putty
```
Host: ec2-user@<your-ec2-public-ip>
Port: 22
Connection → SSH → Auth → Credentials → Select .ppk file
```

---

## Phase 3 - Install Docker

### Step 4 - Install Docker
```bash
sudo yum update -y
sudo yum install docker -y
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker ec2-user
newgrp docker
```

### Step 5 - Verify Docker
```bash
docker --version
docker ps
```

> **Fix if permission denied:**
> ```bash
> sudo chmod 666 /var/run/docker.sock
> ```

### Step 6 - Install Docker Compose
```bash
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
docker-compose --version
```

---

## Phase 4 - Disk and Swap Setup

### Step 7 - Add Swap Memory (Important - Do Before Starting Airflow)
```bash
sudo dd if=/dev/zero of=/swapfile bs=128M count=16
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile swap swap defaults 0 0' | sudo tee -a /etc/fstab
free -h
```

Expected output:
```
Swap: 2.0Gi
```

### Step 8 - Extend Disk (If You Resized EBS Volume in AWS Console)
```bash
sudo growpart /dev/xvda 1
sudo xfs_growfs /
df -h
```

Expected output:
```
/dev/nvme0n1p1   20G   6.9G   14G   35%   /
```

---

## Phase 5 - Setup Airflow

### Step 9 - Create Airflow Directory Structure
```bash
mkdir ~/airflow
cd ~/airflow
mkdir -p dags logs plugins config
```

### Step 10 - Generate Fernet Key and Create .env File
```bash
# Generate Fernet Key
python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
```

Copy the output, then:
```bash
nano ~/airflow/.env
```

Add:
```bash
AIRFLOW_UID=1000
FERNET_KEY=paste-your-generated-key-here
```

Save: `Ctrl+X → Y → Enter`

### Step 11 - Download Airflow Docker Compose File
```bash
cd ~/airflow
curl -LfO 'https://airflow.apache.org/docs/apache-airflow/stable/docker-compose.yaml'
```

### Step 12 - Edit docker-compose.yaml

```bash
nano ~/airflow/docker-compose.yaml
```

Find `_PIP_ADDITIONAL_REQUIREMENTS` under **x-airflow-common** section (first occurrence) and update:
```yaml
_PIP_ADDITIONAL_REQUIREMENTS: ${_PIP_ADDITIONAL_REQUIREMENTS:- apache-airflow-providers-amazon}
```

> **Important:** There are TWO occurrences of `_PIP_ADDITIONAL_REQUIREMENTS`:
> - First one under `x-airflow-common` → **Update this one** ✅
> - Second one under `airflow-init` → **Leave empty** ✅

Save: `Ctrl+X → Y → Enter`

---

## Phase 6 - Start Airflow

### Step 13 - Initialize Airflow Database
```bash
cd ~/airflow
docker-compose up airflow-init
```

Wait for:
```
User "airflow" created with role "Admin"
airflow-init exited with code 0            ← SUCCESS
```

> **Note:** Warning about disk space (< 10 GB) is just a warning, not an error.
> Init completing with code 0 = success ✅

### Step 14 - Start All Airflow Services
```bash
docker-compose up -d
```

### Step 15 - Verify All Containers Running
```bash
docker-compose ps
```

Expected output:
```
airflow-apiserver    → healthy ✅        (port 8080 exposed)
airflow-scheduler    → healthy ✅
airflow-dag-processor→ healthy ✅
airflow-triggerer    → healthy ✅
airflow-worker       → healthy ✅
postgres             → healthy ✅
redis                → healthy ✅
airflow-init         → Exited  ✅        (one-time setup, expected to exit)
```

> **Note:** `airflow-init Exited` is **completely normal and expected**.
> It is a one-time setup container that exits after creating DB and admin user.

### Step 16 - Check Memory After All Containers Start
```bash
free -h
```

Healthy output on m7i-flex.large:
```
Mem:    7.6Gi    4.1Gi    321Mi    ...    3.2Gi   ← available is what matters
Swap:   2.0Gi     46Mi   2.0Gi
```

---

## Phase 7 - Configure Airflow for S3

### Step 17 - Access Airflow UI
```
Browser → http://<your-ec2-public-ip>:8080

Username: airflow
Password: airflow
```

### Step 18 - Setup AWS Connection in UI
```
Airflow UI
      ↓
Admin → Connections → + Add
      ↓
Connection Id  : aws_default
Connection Type: Amazon Web Services
Access Key     : (leave EMPTY)   ← IAM Role handles this
Secret Key     : (leave EMPTY)   ← IAM Role handles this
Extra          : {"region_name": "ap-south-1"}
      ↓
Save
```

---

## Phase 8 - Create and Test S3 DAG

### Step 19 - Create Test DAG

> **Important for Airflow 3.x:** Use `schedule=None` NOT `schedule_interval=None`
> `schedule_interval` was removed in Airflow 3.x and will cause TypeError

```bash
nano ~/airflow/dags/test_s3.py
```

```python
from airflow import DAG
from airflow.providers.amazon.aws.operators.s3 import S3ListOperator
from airflow.operators.python import PythonOperator
from datetime import datetime

with DAG(
    dag_id="test_s3_access",
    start_date=datetime(2024, 1, 1),
    schedule=None,          # ← use schedule not schedule_interval (Airflow 3.x)
    catchup=False
) as dag:

    list_files = S3ListOperator(
        task_id="list_s3_files",
        bucket="your-bucket-name",   # Replace with your bucket
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
```

Save: `Ctrl+X → Y → Enter`

### Step 20 - Trigger DAG and Verify
```
Airflow UI
      ↓
DAGs → test_s3_access
      ↓
Trigger DAG ▶
      ↓
Click on DAG Run → Click "list_s3_files" task → Logs
```

**Success indicators in logs:**
```
Found credentials from IAM Role: airflow-ec2-role  ✅
Getting the list of files from bucket: your-bucket  ✅
Task instance in success state                      ✅
```

**To see actual file list:**
```
Click "list_s3_files" task → XCom tab
→ Shows: ["your-file.txt"]
```

Or check logs of `print_files` task:
```
Files in S3 bucket: ['your-file.txt']
```

---

## Useful Commands Reference

```bash
# Check all containers status
docker-compose ps

# Check memory usage
free -h

# Check disk usage
df -h

# View specific service logs
cd ~/airflow
docker-compose logs airflow-scheduler | tail -30
docker-compose logs airflow-dag-processor | tail -30

# Check if amazon provider is installed
docker exec -it airflow-airflow-scheduler-1 pip3 show apache-airflow-providers-amazon

# List all DAGs
docker exec -it --user airflow airflow-airflow-scheduler-1 airflow dags list

# Restart all services
docker-compose restart

# Stop all services
docker-compose down

# Fresh start (deletes all data)
docker-compose down --volumes --remove-orphans
```

---

## Folder Structure
```
~/airflow/
├── .env                  ← AIRFLOW_UID + FERNET_KEY
├── docker-compose.yaml   ← Airflow services config
├── dags/                 ← Put your DAG files here
│   └── test_s3.py
├── logs/                 ← Task execution logs
├── plugins/              ← Custom plugins
└── config/
    └── airflow.cfg       ← Airflow configuration
```

---

## Common Issues and Fixes

| Issue | Cause | Fix |
|---|---|---|
| Port 8080 disabled when selecting HTTP | HTTP locks to port 80 | Use **Custom TCP** instead |
| `schedule_interval` TypeError | Removed in Airflow 3.x | Use `schedule=None` |
| Permission denied on docker | User not in docker group | `sudo chmod 666 /var/run/docker.sock` |
| Instance unreachable after docker-compose up | RAM exhausted | Add swap memory before starting |
| DAG not appearing in UI | Syntax error in DAG file | Check dag-processor logs |
| S3 access denied | IAM role not attached | Attach IAM role to EC2 instance |
| Disk space warning during init | Less than 10 GB free | Warning only, not error. Resize EBS if needed |
| airflow-init shows Exited | Expected behavior | One-time setup container, ignore |

---

## Key Learnings

1. **IAM Role > Access Keys** - Attach IAM role to EC2, leave connection keys empty in Airflow
2. **Custom TCP for port 8080** - Never use HTTP type for Airflow UI port
3. **Airflow 3.x breaking change** - `schedule_interval` replaced by `schedule`
4. **S3ListOperator output** - Results stored in XCom, not printed in logs
5. **airflow-init Exited** - Normal behavior, not an error
6. **Available RAM > Free RAM** - Linux uses spare RAM as cache, check "available" column
7. **Swap memory** - Always add before starting Docker on instances with ≤ 8 GB RAM
8. **Extend filesystem** - After resizing EBS in AWS console, run `growpart` + `xfs_growfs`

---

*Setup completed and verified on: 12-Apr-2026*
*Airflow Version: 3.2.0*
*Amazon Provider Version: 9.23.0*
