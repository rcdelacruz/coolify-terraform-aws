# Changelog

All notable changes to this project will be documented in this file.

## [2.0.0] - 2025-07-10 - Multi-Server Architecture

### Added
- **Multi-server architecture** with separate control and remote servers
- **t4g.micro control server** for Coolify dashboard and management (~$8/month)
- **t4g.large remote servers** for application deployment (~$53/month each)
- **Scalable remote server count** - deploy 1 to N servers
- **Separate user data scripts** optimized for each server type
- **Enhanced security groups** with role-specific access rules
- **Cost optimization features** with detailed cost breakdowns
- **Comprehensive documentation** including setup and troubleshooting guides
- **GitHub Actions workflow** for Terraform validation

### Changed
- **Architecture redesign** from single-server to multi-server setup
- **Cost reduction** of ~85% compared to single large server
- **Improved security** with isolated control plane
- **Better resource utilization** with dedicated application servers
- **Enhanced monitoring** with server-type specific metrics

### Migration from v1.x
- **Breaking change**: Complete architecture overhaul
- **Manual migration required**: Deploy new infrastructure and migrate applications
- **Cost impact**: Significant cost reduction for most workloads
- **Performance improvement**: Better isolation and dedicated resources

### Technical Details
- Control server runs Coolify dashboard with minimal resource usage
- Remote servers handle all application deployments with Docker optimization
- Private network communication between control and remote servers
- Automated backup strategies per server type
- CloudWatch monitoring with server-specific namespaces

## [1.0.0] - 2025-07-09 - Initial Release

### Added
- Single t4g.large server Coolify deployment
- Basic monitoring and backup capabilities
- Cloudflare Tunnel integration
- Terraform infrastructure as code
- Security hardening with UFW and fail2ban

---

**Migration Guide**: See `docs/migration-guide.md` for detailed instructions on migrating from v1.x to v2.0.