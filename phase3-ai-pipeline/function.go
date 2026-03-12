package analyzer

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"

	"cloud.google.com/go/pubsub"
	vision "cloud.google.com/go/vision/apiv1"
	"github.com/GoogleCloudPlatform/functions-framework-go/functions"
)

var (
	projectID = os.Getenv("PROJECT_ID")
	topicID   = os.Getenv("PUBSUB_TOPIC")
)

func init() {
	functions.HTTP("AnalyzeImage", AnalyzeImage)
}

// AnalyzeRequest は Cloud Run API から送られるリクエストの形式
type AnalyzeRequest struct {
	BucketName string `json:"bucket_name"`
	ObjectName string `json:"object_name"`
}

// AnalysisResult は Vision API の解析結果
type AnalysisResult struct {
	BucketName  string   `json:"bucket_name"`
	ObjectName  string   `json:"object_name"`
	Labels      []string `json:"labels"`
	Description string   `json:"description"`
}

// AnalyzeImage は HTTP トリガーで呼ばれる Cloud Function
// Phase1 のアップロード API がファイル保存後にこの URL を叩く
func AnalyzeImage(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "POST only", http.StatusMethodNotAllowed)
		return
	}

	var req AnalyzeRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "リクエストボディのパース失敗", http.StatusBadRequest)
		return
	}

	if req.BucketName == "" || req.ObjectName == "" {
		http.Error(w, "bucket_name と object_name は必須", http.StatusBadRequest)
		return
	}

	ctx := r.Context()

	// Vision API で解析
	result, err := analyzeWithVision(ctx, req.BucketName, req.ObjectName)
	if err != nil {
		log.Printf("Vision API エラー: %v", err)
		http.Error(w, "画像解析失敗", http.StatusInternalServerError)
		return
	}

	// Pub/Sub に結果を発行
	if err := publishResult(ctx, result); err != nil {
		log.Printf("Pub/Sub 発行エラー: %v", err)
		// Pub/Sub 失敗でも解析結果は返す
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(result)
}

func analyzeWithVision(ctx context.Context, bucketName, objectName string) (*AnalysisResult, error) {
	client, err := vision.NewImageAnnotatorClient(ctx)
	if err != nil {
		return nil, fmt.Errorf("Vision クライアント初期化失敗: %w", err)
	}
	defer client.Close()

	// GCS の画像を直接参照（ダウンロード不要）
	imageURI := fmt.Sprintf("gs://%s/%s", bucketName, objectName)
	image := vision.NewImageFromURI(imageURI)

	// ラベル検出（何が写っているか最大10件）
	annotations, err := client.DetectLabels(ctx, image, nil, 10)
	if err != nil {
		return nil, fmt.Errorf("ラベル検出失敗: %w", err)
	}

	// 確信度70%以上のラベルだけ採用
	labels := make([]string, 0)
	for _, a := range annotations {
		if a.Score > 0.7 {
			labels = append(labels, a.Description)
		}
	}

	description := "検出なし"
	if len(labels) > 0 {
		description = labels[0]
	}

	log.Printf("解析完了 gs://%s/%s → %v", bucketName, objectName, labels)

	return &AnalysisResult{
		BucketName:  bucketName,
		ObjectName:  objectName,
		Labels:      labels,
		Description: description,
	}, nil
}

func publishResult(ctx context.Context, result *AnalysisResult) error {
	client, err := pubsub.NewClient(ctx, projectID)
	if err != nil {
		return fmt.Errorf("Pub/Sub クライアント初期化失敗: %w", err)
	}
	defer client.Close()

	data, err := json.Marshal(result)
	if err != nil {
		return err
	}

	topic := client.Topic(topicID)
	msg := &pubsub.Message{
		Data: data,
		Attributes: map[string]string{
			"bucket": result.BucketName,
			"object": result.ObjectName,
		},
	}

	msgID, err := topic.Publish(ctx, msg).Get(ctx)
	if err != nil {
		return fmt.Errorf("Pub/Sub 発行失敗: %w", err)
	}

	log.Printf("Pub/Sub 発行完了 (messageID: %s)", msgID)
	return nil
}
