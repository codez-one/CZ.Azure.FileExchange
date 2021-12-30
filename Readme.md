# Cz.Tools.FileExchange

This project provides a website to share fast files with the help of azure.
You get an upload website that looks like this:

![Upload](docs/.assets/dbf1f27a-e386-4b94-bd34-418bca1a057a.png)

The important thing there is the guid the is displayed after uploading a file.
This can be used on the download page:

![Download](docs/.assets/ce9c3c1a-eb2d-4222-befb-fc57b8823404.png)

## Deployment

- compile the `main.bicep` file
- then configure your azure devops pipeline for static websites
- enjoy