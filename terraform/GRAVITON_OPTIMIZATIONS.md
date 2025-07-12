# Graviton ARM64 High Container Density Optimizations

This document outlines the Graviton-specific optimizations applied to remote servers for running high-density container workloads efficiently.

## Overview

The optimizations focus on six key areas for Graviton ARM64 processors:
1. **ARM64-Specific Kernel Tuning** - CPU scheduling and memory management
2. **High Container Density** - System limits for 1000+ containers
3. **Network Optimization** - BBR congestion control and high concurrency
4. **I/O Performance** - Optimized for container layers and volumes
5. **Memory Management** - Huge pages and efficient allocation
6. **Automated Management** - Scripts for monitoring and optimization

## Graviton-Specific Optimizations

### 1. ARM64 CPU and Scheduling

**CPU Governor**:
```bash
scaling_governor = "performance"  # Optimal for Graviton processors
```

**Kernel Scheduling Parameters**:
```bash
kernel.sched_migration_cost_ns = 500000      # Optimized for ARM64
kernel.sched_min_granularity_ns = 10000000   # Better multi-container performance
kernel.sched_wakeup_granularity_ns = 15000000 # Reduced context switching
```

### 2. High Container Density Configuration

**System Limits (Extreme Density)**:
- **File Descriptors**: 1,048,576 (up from 65,535)
- **Processes**: 1,048,576 per user
- **Memory Lock**: Unlimited
- **Connection Tracking**: 1,048,576 concurrent connections

**Docker Configuration**:
```json
{
  "default-ulimits": {
    "nofile": {"Hard": 1048576, "Soft": 1048576},
    "nproc": {"Hard": 1048576, "Soft": 1048576},
    "memlock": {"Hard": -1, "Soft": -1}
  },
  "max-concurrent-downloads": 10,
  "max-concurrent-uploads": 10,
  "live-restore": true,
  "userland-proxy": false
}
```

### 3. Network Optimizations for Container Density

**BBR Congestion Control**:
```bash
net.ipv4.tcp_congestion_control = bbr  # Better throughput for containers
```

**Buffer Sizes**:
```bash
net.core.rmem_max = 16777216           # 16MB receive buffer
net.core.wmem_max = 16777216           # 16MB send buffer
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
```

**Connection Tracking**:
```bash
net.netfilter.nf_conntrack_max = 1048576      # 1M connections
net.netfilter.nf_conntrack_buckets = 262144   # Hash table size
```

### 4. Memory Management for High Density

**Huge Pages Configuration**:
- Automatically configured for 25% of available memory
- 2MB huge pages for better memory efficiency
- Reduces TLB pressure with many containers

**Memory Parameters**:
```bash
vm.min_free_kbytes = 131072        # Keep more memory free
vm.zone_reclaim_mode = 0           # Prefer remote memory over swap
vm.max_map_count = 2147483647      # Support many memory mappings
```

### 5. I/O Optimization

**I/O Scheduler**:
```bash
# mq-deadline scheduler for all block devices
echo mq-deadline > /sys/block/*/queue/scheduler
```

**Read-ahead Optimization**:
```bash
# 1MB read-ahead for container image layers
echo 1024 > /sys/block/*/bdi/read_ahead_kb
```

## Container Management Scripts

### 1. Density Monitoring (`container-density-monitor.sh`)

**Features**:
- Real-time container count and resource usage
- Memory, CPU, and disk utilization
- Top containers by resource consumption
- Automatic warnings for resource thresholds

**Usage**:
```bash
/usr/local/bin/container-density-monitor.sh
```

### 2. Automated Cleanup (`container-density-cleanup.sh`)

**Features**:
- Removes stopped containers automatically
- Cleans unused images and volumes
- Prunes build cache (keeps 10GB)
- Optimized for high-turnover environments

**Scheduled**: Daily at 2 AM via cron

### 3. Dynamic Optimization (`container-optimize.sh`)

**Features**:
- Adjusts kernel parameters based on container count
- Scales connection tracking dynamically
- Optimizes memory management for current load
- Runs every 15 minutes automatically

## Performance Benefits

### Expected Container Capacity

**Small Containers** (128MB RAM each):
- **t4g.medium** (4GB): ~25-30 containers
- **t4g.large** (8GB): ~50-60 containers  
- **t4g.xlarge** (16GB): ~100-120 containers
- **t4g.2xlarge** (32GB): ~200-250 containers

**Medium Containers** (512MB RAM each):
- **t4g.medium**: ~6-8 containers
- **t4g.large**: ~12-15 containers
- **t4g.xlarge**: ~25-30 containers
- **t4g.2xlarge**: ~50-60 containers

### Network Performance

- **Concurrent Connections**: Up to 1M per server
- **Throughput**: Optimized with BBR congestion control
- **Latency**: Reduced with optimized kernel scheduling

### I/O Performance

- **Container Startup**: Faster with optimized read-ahead
- **Image Pulls**: Concurrent downloads (10 simultaneous)
- **Volume Access**: Optimized with mq-deadline scheduler

## Monitoring and Alerts

### Automatic Monitoring

- **Resource Usage**: Every 6 hours
- **Optimization**: Every 15 minutes  
- **Cleanup**: Daily at 2 AM

### Warning Thresholds

- **Memory**: Alert at 85% usage
- **Disk**: Alert at 85% usage
- **High Density**: Info message at 100+ containers

### Log Files

- `/var/log/container-monitor.log` - Monitoring reports
- `/var/log/container-optimize.log` - Optimization actions
- `/var/log/container-cleanup.log` - Cleanup operations

## Best Practices for High Density

### 1. Container Resource Limits

Always set resource limits:
```yaml
resources:
  limits:
    memory: "512Mi"
    cpu: "500m"
  requests:
    memory: "256Mi" 
    cpu: "250m"
```

### 2. Health Checks

Implement proper health checks to avoid zombie containers:
```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
  interval: 30s
  timeout: 10s
  retries: 3
```

### 3. Log Management

Use structured logging with size limits:
```yaml
logging:
  driver: "json-file"
  options:
    max-size: "10m"
    max-file: "2"
```

## Troubleshooting

### High Memory Usage

```bash
# Check container memory usage
docker stats --no-stream

# Check system memory
free -h

# Check for memory leaks
cat /proc/meminfo
```

### Network Issues

```bash
# Check connection tracking
cat /proc/sys/net/netfilter/nf_conntrack_count
cat /proc/sys/net/netfilter/nf_conntrack_max

# Check network performance
ss -tuln | wc -l
```

### I/O Performance

```bash
# Check I/O wait
iostat -x 1

# Check disk usage
df -h /data
du -sh /data/docker
```

This configuration enables your Graviton remote servers to efficiently handle high container density workloads while maintaining optimal performance.
