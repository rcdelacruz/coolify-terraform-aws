# Migration Guide: Single Server → Multi-Server Architecture

This guide helps you migrate from the single-server Coolify setup to the new multi-server architecture.

## Overview

The multi-server architecture provides:
- **85% cost reduction** for most workloads
- **Better performance isolation** between applications
- **Improved fault tolerance** with dedicated servers
- **Granular scaling** based on actual needs

## Pre-Migration Checklist

### 1. Backup Current Setup
```bash
# SSH into current Coolify server
ssh -i ~/.ssh/your-key.pem ubuntu@CURRENT_SERVER_IP

# Create comprehensive backup
sudo tar -czf /tmp/coolify-migration-backup.tar.gz \
  /data/coolify \
  /data/docker/volumes \
  --exclude='*/logs/*'

# Upload to S3 for safety
aws s3 cp /tmp/coolify-migration-backup.tar.gz s3://your-backup-bucket/migration/
```

### 2. Document Current Applications
```bash
# List all applications
curl -s http://localhost:8000/api/applications | jq '.[] | {name, status, git_repository}'

# Export environment variables
# Do this through Coolify dashboard: Applications → Settings → Environment Variables → Export
```

### 3. Note Custom Configurations
- Custom domain mappings
- SSL certificates
- Database configurations
- Third-party integrations
- Cloudflare Tunnel settings

## Migration Process

### Phase 1: Deploy New Infrastructure

1. **Switch to multi-server branch:**
   ```bash
   git checkout multi-server-architecture
   cd terraform/
   ```

2. **Configure new setup:**
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your preferences
   ```

3. **Deploy new infrastructure:**
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

4. **Note new server details:**
   ```bash
   terraform output setup_instructions
   ```

### Phase 2: Set Up New Coolify

1. **Access new Coolify dashboard:**
   ```bash
   open http://$(terraform output -raw control_server_public_ip):8000
   ```

2. **Complete initial setup:**
   - Create admin account (use same credentials)
   - Configure basic settings
   - Add remote servers (use private IPs from terraform output)

3. **Verify server connectivity:**
   - Check all remote servers show as "Connected"
   - Test deployment with a simple application

### Phase 3: Migrate Applications

#### For Git-Based Applications

1. **Recreate applications in new Coolify:**
   - Use same Git repository
   - Choose appropriate remote server
   - Configure environment variables
   - Set up domains and SSL

2. **Deploy and test:**
   - Deploy application
   - Verify functionality
   - Test all endpoints

#### For Docker Image Applications

1. **Recreate using same Docker images:**
   - Use same image tags
   - Configure ports and volumes
   - Set environment variables
   - Deploy to remote server

#### For Database Applications

1. **Deploy database on remote server:**
   - Choose server with adequate resources
   - Use same database version
   - Configure persistent volumes

2. **Migrate data:**
   ```bash
   # Export from old server
   docker exec OLD_DB_CONTAINER pg_dump dbname > backup.sql
   
   # Import to new server
   docker exec -i NEW_DB_CONTAINER psql dbname < backup.sql
   ```

### Phase 4: DNS and Traffic Migration

#### Without Cloudflare Tunnel

1. **Update DNS records:**
   ```bash
   # Point domains to new remote servers
   # Use public IPs from terraform output
   ```

2. **Test with hosts file first:**
   ```bash
   # Add to /etc/hosts for testing
   NEW_REMOTE_IP yourdomain.com
   ```

#### With Cloudflare Tunnel

1. **Update tunnel configuration:**
   ```yaml
   # New hostname mappings
   coolify.yourdomain.com → CONTROL_PRIVATE_IP:8000
   app1.yourdomain.com → REMOTE1_PRIVATE_IP:80
   app2.yourdomain.com → REMOTE2_PRIVATE_IP:80
   ```

2. **Deploy tunnel changes:**
   ```bash
   cloudflared tunnel route dns TUNNEL_ID app1.yourdomain.com
   ```

### Phase 5: Verification and Cleanup

1. **Comprehensive testing:**
   - Test all applications
   - Verify SSL certificates
   - Check database connectivity
   - Validate backup processes

2. **Monitor for 24-48 hours:**
   - Watch CloudWatch metrics
   - Check application logs
   - Monitor user reports

3. **Cleanup old infrastructure:**
   ```bash
   # Only after confirming everything works
   # terraform destroy (in old single-server directory)
   ```

## Rollback Plan

If issues arise during migration:

1. **Immediate rollback:**
   ```bash
   # Revert DNS to old server
   # Keep old server running during migration
   ```

2. **Fix issues and retry:**
   - Address specific problems
   - Test fixes on new infrastructure
   - Retry migration when confident

## Post-Migration Optimization

### 1. Resource Right-Sizing
```bash
# Monitor actual usage for 2-4 weeks
# Adjust instance types based on utilization
```

### 2. Cost Optimization
```bash
# Consider Reserved Instances for stable workloads
# Implement lifecycle policies for S3 backups
# Optimize CloudWatch log retention
```

### 3. Performance Tuning
```bash
# Distribute applications across remote servers
# Optimize Docker resource limits
# Implement health checks and monitoring
```

## Troubleshooting Migration Issues

### Application Won't Start
```bash
# Check resource limits on remote server
free -h
df -h /data

# Verify environment variables
# Check Docker logs
docker logs CONTAINER_NAME
```

### Database Connection Issues
```bash
# Verify network connectivity
telnet DB_SERVER_IP 5432

# Check database credentials
# Verify database is running
docker ps | grep postgres
```

### SSL Certificate Problems
```bash
# Check domain configuration
# Verify DNS propagation
nslookup yourdomain.com

# Regenerate certificates if needed
```

## Success Metrics

After successful migration, you should see:
- **Reduced monthly costs** (typically 60-85% reduction)
- **Improved application isolation** and stability
- **Better resource utilization** across servers
- **Maintained or improved performance**
- **Simplified scaling** for future growth

---

**Need Help?** Check the troubleshooting guide or create an issue in the GitHub repository with details about your specific migration challenge.