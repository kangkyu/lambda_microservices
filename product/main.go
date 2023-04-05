package main

import (
	"context"
	"encoding/json"
	"net/http"
	"os"
	"time"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
)

type timeEvent struct {
	Time string `json:"time"`
}

func handleRequest(ctx context.Context, request events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	tableName := os.Getenv("PRODUCT_TABLE")

	switch request.HTTPMethod {
	case "GET":
		t := timeEvent{Time: time.Now().String()}
		b, err := json.Marshal(t)
		if err != nil {
			return events.APIGatewayProxyResponse{}, err
		}

		return events.APIGatewayProxyResponse{
			StatusCode: http.StatusOK,
			Body:       string(b),
		}, nil
	case "POST":
		ctx := context.TODO()
		cfg, err := config.LoadDefaultConfig(ctx, config.WithRegion("us-west-2"))
		if err != nil {
			return events.APIGatewayProxyResponse{}, err
		}

		dynamoClient := dynamodb.NewFromConfig(cfg)
		item, err := attributevalue.MarshalMap(map[string]string{
			"product_id": "you-know-what",
		})
		if err != nil {
			return events.APIGatewayProxyResponse{}, err
		}
		input := &dynamodb.PutItemInput{
			TableName: aws.String(tableName),
			Item:      item,
		}
		output, err := dynamoClient.PutItem(ctx, input)
		if err != nil {
			return events.APIGatewayProxyResponse{}, err
		}
		attrs := output.Attributes
		a, err := json.Marshal(attrs)
		if err != nil {
			return events.APIGatewayProxyResponse{}, err
		}

		return events.APIGatewayProxyResponse{
			StatusCode: http.StatusOK,
			Body:       string(a),
		}, nil
	}

	return events.APIGatewayProxyResponse{
		StatusCode: http.StatusOK,
		Body:       "otherwise",
	}, nil
}

func main() {
	lambda.Start(handleRequest)
}
