terraform{

    required_version= "~>1.14.0"

    required_providers{
        aws={
            source="hashicorp/aws"
            version="~>5.0"
        }
    }

    backend "s3" {
        bucket="terraform-course-urdrdrd-remote-backend-east-2"
        key="remote/03-s3-backend/state.tfstate"
        region="us-east-2"
        use_lockfile=true
        encrypt=true
    }
}

