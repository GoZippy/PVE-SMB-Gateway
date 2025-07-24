# Repository Name Correction

## Issue
The documentation contained references to `ZippyNetworks` organization, but the actual GitHub repository is under the `GoZippy` organization.

## Correct Repository Information

- **Organization**: GoZippy (not ZippyNetworks)
- **Repository**: https://github.com/GoZippy/PVE-SMB-Gateway.git
- **Repository Name**: PVE-SMB-Gateway (with capital letters)

## Files Updated

The following files have been corrected to use the proper repository references:

- `README.md` - Build status badge and download links
- `ALPHA_RELEASE_NOTES.md` - Download links and GitHub references
- `docs/GETTING_STARTED.md` - Clone instructions and release page links
- `.github/workflows/cluster-test.yml` - Repository parameter

## Remaining References

Some files may still contain references to `ZippyNetworks` that need to be updated:

- `scripts/prepare_v1_release.sh`
- `RELEASE_v1.0.0_ADMINISTRATOR.md`
- `RELEASE_SUMMARY.md`
- `docs/USER_GUIDE.md`
- `docs/GITHUB_SETUP.md`
- `docs/DEV_GUIDE.md`
- `debian/copyright`
- `ADMINISTRATOR_QUICK_START.md`

## Action Required

When preparing releases or updating documentation, ensure all references use:
- **Organization**: `GoZippy`
- **Repository**: `PVE-SMB-Gateway`
- **Full URL**: `https://github.com/GoZippy/PVE-SMB-Gateway.git`

## Note

This correction ensures that users can properly clone the repository and access releases using the correct GitHub URLs. 