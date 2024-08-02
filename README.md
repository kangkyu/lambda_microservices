# lambda_microservices

Use AWS Lambda as microservice, and build event-driven structure.

```sh
terraform init
AWS_PROFILE=admin terraform apply
```

Put your profile name in place of 'admin'.

Try
('yglb9j7tna' part will be different)

```sh
export BASE_URL='https://yglb9j7tna.execute-api.us-west-2.amazonaws.com/lambda'
curl "$BASE_URL/translate" -X POST -d '{"translate_id": "abc"}'
```

After trying, do not forget to run `terraform destroy`

```sh
AWS_PROFILE=admin terraform destroy
```
