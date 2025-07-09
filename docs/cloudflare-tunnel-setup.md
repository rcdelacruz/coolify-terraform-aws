# Cloudflare Tunnel Setup Guide for Coolify

This guide explains how to properly configure Cloudflare Tunnel with your Coolify deployment using the `*.stratpoint.io` wildcard domain.

## Prerequisites

1. Deployed Coolify server using this Terraform configuration
2. Cloudflare account with `stratpoint.io` domain
3. Access to Cloudflare Zero Trust dashboard

## Step 1: Create Cloudflare Tunnel

1. Go to [Cloudflare Zero Trust Dashboard](https://one.dash.cloudflare.com/)
2. Navigate to **Networks** → **Tunnels**
3. Click **Create a tunnel**
4. Choose **Cloudflared** as the connector
5. Name your tunnel (e.g., `coolify-stratpoint`)
6. Click **Save tunnel**

## Step 2: Install Cloudflare Tunnel

**Note:** You don't need to install cloudflared on your server. The tunnel will run from your local machine or a separate server.

1. Download cloudflared on your local machine or management server
2. Copy the tunnel token from the Cloudflare dashboard
3. Run the tunnel:
   ```bash
   cloudflared tunnel run --token <your-tunnel-token>
   ```

## Step 3: Configure Hostname Mappings

In the Cloudflare dashboard, configure these **Public Hostnames**:

### Required Mappings:

1. **Coolify Dashboard:**
   - **Public hostname:** `coolify.stratpoint.io`
   - **Service:** `HTTP://YOUR_SERVER_PRIVATE_IP:8000`
   - **Path:** (leave empty)

2. **Realtime Server:**
   - **Public hostname:** `realtime.stratpoint.io`
   - **Service:** `HTTP://YOUR_SERVER_PRIVATE_IP:6001`
   - **Path:** (leave empty)

3. **Terminal WebSocket:**
   - **Public hostname:** `terminal.stratpoint.io`
   - **Service:** `HTTP://YOUR_SERVER_PRIVATE_IP:6002`
   - **Path:** `/ws`

4. **Wildcard for Apps:**
   - **Public hostname:** `*.stratpoint.io`
   - **Service:** `HTTP://YOUR_SERVER_PRIVATE_IP:80`
   - **Path:** (leave empty)

## Step 4: Update Coolify Configuration

SSH into your Coolify server and update the configuration:

```bash
ssh -i ~/.ssh/your-key.pem ubuntu@YOUR_SERVER_IP
```

Edit Coolify's environment file:
```bash
sudo nano /data/coolify/source/.env
```

Add these lines to the `.env` file:
```bash
PUSHER_HOST=realtime.stratpoint.io
PUSHER_PORT=443
```

## Step 5: Restart Coolify

After updating the `.env` file, restart Coolify:

```bash
curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash
```

## Step 6: Verify Setup

1. **Access Coolify Dashboard:** https://coolify.stratpoint.io
2. **Check Realtime Connection:** Should work automatically with the new PUSHER settings
3. **Test Terminal Access:** Terminal should work in the Coolify dashboard
4. **Deploy a Test App:** Should be accessible at `yourapp.stratpoint.io`

## DNS Configuration

Make sure your `stratpoint.io` domain is properly configured in Cloudflare:

1. Go to **DNS** → **Records** in Cloudflare dashboard
2. Ensure you have proper DNS records pointing to Cloudflare's proxy
3. The tunnel will handle the actual routing to your server

## Troubleshooting

### Common Issues:

1. **Tunnel not connecting:**
   - Check if cloudflared is running with the correct token
   - Verify your server's private IP is correct
   - Ensure ports 80, 6001, 6002, 8000 are open on your server

2. **Realtime features not working:**
   - Verify `PUSHER_HOST` and `PUSHER_PORT` are correctly set
   - Check that `realtime.stratpoint.io` is properly mapped
   - Restart Coolify after making changes

3. **Apps not accessible:**
   - Verify the wildcard `*.stratpoint.io` mapping
   - Check that your apps are running on port 80 internally
   - Ensure Coolify's Traefik proxy is configured correctly

### Debug Commands:

```bash
# Check if Coolify services are running
docker ps | grep coolify

# Check Coolify logs
docker logs coolify-realtime

# Check if ports are listening
netstat -tlnp | grep -E ':(80|6001|6002|8000)'

# Test internal connectivity
curl -I localhost:8000
curl -I localhost:6001
```

## Security Considerations

1. **Restrict Dashboard Access:** Consider limiting `coolify.stratpoint.io` to specific IPs
2. **Use Strong Passwords:** Ensure your Coolify admin account has a strong password
3. **Regular Updates:** Keep Coolify updated regularly
4. **Monitor Logs:** Check both Cloudflare and Coolify logs regularly

## Next Steps

After setup is complete:

1. **Configure SSL:** Cloudflare automatically handles SSL termination
2. **Set up monitoring:** Use Cloudflare analytics and your CloudWatch metrics
3. **Deploy applications:** Your apps will be accessible at `appname.stratpoint.io`
4. **Configure backups:** The Terraform setup includes automated S3 backups

## Additional Resources

- [Coolify Documentation](https://coolify.io/docs)
- [Cloudflare Tunnel Documentation](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/)
- [Cloudflare Zero Trust Dashboard](https://one.dash.cloudflare.com/)
