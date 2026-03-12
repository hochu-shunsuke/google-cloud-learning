package main

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	"cloud.google.com/go/bigquery"
)

var (
	projectID = os.Getenv("PROJECT_ID")
	datasetID = os.Getenv("BQ_DATASET")
	tableID   = os.Getenv("BQ_TABLE")
)

type PubSubMessage struct {
	Message struct {
		Data      string `json:"data"`
		MessageID string `json:"messageId"`
	} `json:"message"`
}

type AnalysisResult struct {
	BucketName  string   `json:"bucket_name"`
	ObjectName  string   `json:"object_name"`
	Labels      []string `json:"labels"`
	Description string   `json:"description"`
}

type ResultRow struct {
	BucketName  string    `bigquery:"bucket_name"`
	ObjectName  string    `bigquery:"object_name"`
	Labels      string    `bigquery:"labels"`
	Description string    `bigquery:"description"`
	AnalyzedAt  time.Time `bigquery:"analyzed_at"`
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	http.HandleFunc("/", handlePubSub)
	http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	log.Printf("BigQuery subscriber 起動 (port %s)", port)
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatal(err)
	}
}

func handlePubSub(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "POST only", http.StatusMethodNotAllowed)
		return
	}

	var msg PubSubMessage
	if err := json.NewDecoder(r.Body).Decode(&msg); err != nil {
		http.Error(w, "リクエストパース失敗", http.StatusBadRequest)
		return
	}

	data, err := base64.StdEncoding.DecodeString(msg.Message.Data)
	if err != nil {
		http.Error(w, "Base64デコード失敗", http.StatusBadRequest)
		return
	}

	var result AnalysisResult
	if err := json.Unmarshal(data, &result); err != nil {
		http.Error(w, "JSONパース失敗", http.StatusBadRequest)
		return
	}

	log.Printf("受信: %s → %v", result.ObjectName, result.Labels)

	if err := insertToBigQuery(r.Context(), result); err != nil {
		http.Error(w, "BigQuery挿入失敗", http.StatusInternalServerError)
		log.Printf("bq insert error: %v", err)
		return
	}

	log.Printf("BigQuery挿入完了: %s", result.ObjectName)
	w.WriteHeader(http.StatusOK)
}

func insertToBigQuery(ctx context.Context, result AnalysisResult) error {
	client, err := bigquery.NewClient(ctx, projectID)
	if err != nil {
		return err
	}
	defer client.Close()

	row := &ResultRow{
		BucketName:  result.BucketName,
		ObjectName:  result.ObjectName,
		Labels:      strings.Join(result.Labels, ","),
		Description: result.Description,
		AnalyzedAt:  time.Now().UTC(),
	}

	return client.Dataset(datasetID).Table(tableID).Inserter().Put(ctx, row)
}
