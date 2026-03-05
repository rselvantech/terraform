terraform{
    required_version="~>1.14.0"

    required_providers{
        source="hashicorp/aws"
        version="~>6.30.0"
    }

    backend "s3"{
        encrypt=true
        use_lockfile=true
        # bucket, key, and region are supplied via -backend-config at init time
    }
}