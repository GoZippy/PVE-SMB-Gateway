# PVE SMB Gateway - Quick Start Guide

## Deployment Instructions

1. **Transfer files to Proxmox host:**
   `ash
   scp -r deployment-package root@your-proxmox-host:/tmp/
   `

2. **SSH to Proxmox host:**
   `ash
   ssh root@your-proxmox-host
   `

3. **Navigate to deployment directory:**
   `ash
   cd /tmp/deployment-package
   `

4. **Make scripts executable:**
   `ash
   chmod +x scripts/*.sh deploy.sh
   `

5. **Run deployment:**
   `ash
   ./deploy.sh
   `

6. **Run pre-flight check:**
   `ash
   ./scripts/preflight_check.sh
   `

7. **Start testing:**
   `ash
   ./scripts/run_all_tests.sh
   `

## Important Notes

- Always test in a non-production environment first
- Have backups of your Proxmox configuration
- Keep the rollback script ready: \./scripts/rollback.sh\
- Follow the testing checklist: \LIVE_TESTING_CHECKLIST.md\

## Support

For issues or questions, contact: eric@gozippy.com
