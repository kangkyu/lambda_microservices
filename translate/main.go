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
	"github.com/aws/aws-sdk-go-v2/service/sqs"
)

type timeEvent struct {
	Time string `json:"time"`
}

func handleRequest(ctx context.Context, request events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	tableName := os.Getenv("TRANSLATE_TABLE")
	queueUrl := os.Getenv("SENTENCE_QUEUE_URL")

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

		body := make(map[string]string)
		if json.Valid([]byte(request.Body)) {
			json.Unmarshal([]byte(request.Body), &body)
		} else {
			return events.APIGatewayProxyResponse{
				StatusCode: http.StatusBadRequest,
				Body:       "",
			}, nil
		}
		item, err := attributevalue.MarshalMap(body)
		if err != nil {
			return events.APIGatewayProxyResponse{}, err
		}

		// save to dynamodb
		dynamoClient := dynamodb.NewFromConfig(cfg)
		putItemInput := dynamodb.PutItemInput{
			TableName: aws.String(tableName),
			Item:      item,
		}
		_, err := dynamoClient.PutItem(ctx, &putItemInput)
		if err != nil {
			return events.APIGatewayProxyResponse{}, err
		}

		// send it to sqs
		sqsClient := sqs.NewFromConfig(cfg)

		messageBody := "hello" // temporary translated sentence
		sendMessageInput := sqs.SendMessageInput{
			MessageBody: &messageBody,
			QueueUrl:    aws.String(queueUrl),
		}
		_, err = sqsClient.SendMessage(ctx, &sendMessageInput)
		if err != nil {
			return events.APIGatewayProxyResponse{}, err
		}

		return events.APIGatewayProxyResponse{
			StatusCode: http.StatusCreated,
			Body:       "successful",
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
