cloudstack-templates
====================

## Pre built templates

Pre-built templates can be found on our releases page https://github.com/imduffy15/cloudstack-templates/releases

These pre-built templates are built on Virtual Machines sponsered by <https://www.exoscale.ch/>

![ExoScale](https://www.exoscale.ch/static/img/exoscale-logo-full-black.svg)

## Building the template yourself:

Before using, I recommend you set the following in your `.bashrc` or
`.bash_profile`. It will ensure all of the ISO's downloaded reside in a single
location instead of saving them in each folder.

    export PACKER_CACHE_DIR="~/packer_cache"

After that all you need to do is run:

	packer build template.json
