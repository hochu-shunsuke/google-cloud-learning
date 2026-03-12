package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"time"

	"cloud.google.com/go/storage"
)

var bucketName = os.Getenv("BUCKET_NAME")

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", handleHealth)
	mux.HandleFunc("POST /upload", handleUpload)
	mux.HandleFunc("GET /images", handleListImages)

	log.Printf("Server starting on port %s", port)
	if err := http.ListenAndServe(":"+port, mux); err != nil {
		log.Fatal(err)
	}
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"status": "ok",
		"time":   time.Now().Format(time.RFC3339),
	})
}

func handleUpload(w http.ResponseWriter, r *http.Request) {
	// 最大 10MB
	r.Body = http.MaxBytesReader(w, r.Body, 10<<20)
	if err := r.ParseMultipartForm(10 << 20); err != nil {
		http.Error(w, "ファイルが大きすぎます（最大10MB）", http.StatusBadRequest)
		return
	}

	file, header, err := r.FormFile("image")
	if err != nil {
		http.Error(w, "imageフィールドが見つかりません", http.StatusBadRequest)
		return
	}
	defer file.Close()

	// ファイル名にタイムスタンプを付与して重複防止
	objectName := fmt.Sprintf("uploads/%d-%s", time.Now().UnixNano(), header.Filename)

	ctx := context.Background()
	client, err := storage.NewClient(ctx)
	if err != nil {
		http.Error(w, "Storage クライアント初期化失敗", http.StatusInternalServerError)
		log.Printf("storage.NewClient: %v", err)
		return
	}
	defer client.Close()

	wc := client.Bucket(bucketName).Object(objectName).NewWriter(ctx)
	wc.ContentType = header.Header.Get("Content-Type")

	if _, err := io.Copy(wc, file); err != nil {
		http.Error(w, "アップロード失敗", http.StatusInternalServerError)
		log.Printf("io.Copy: %v", err)
		return
	}
	if err := wc.Close(); err != nil {
		http.Error(w, "ファイルの保存失敗", http.StatusInternalServerError)
		log.Printf("wc.Close: %v", err)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(map[string]string{
		"message": "アップロード成功",
		"object":  objectName,
		"bucket":  bucketName,
	})
}

func handleListImages(w http.ResponseWriter, r *http.Request) {
	ctx := context.Background()
	client, err := storage.NewClient(ctx)
	if err != nil {
		http.Error(w, "Storage クライアント初期化失敗", http.StatusInternalServerError)
		log.Printf("storage.NewClient: %v", err)
		return
	}
	defer client.Close()

	var images []map[string]string
	it := client.Bucket(bucketName).Objects(ctx, &storage.Query{Prefix: "uploads/"})
	for {
		attrs, err := it.Next()
		if err != nil {
			break
		}
		images = append(images, map[string]string{
			"name":    attrs.Name,
			"size":    fmt.Sprintf("%d bytes", attrs.Size),
			"updated": attrs.Updated.Format(time.RFC3339),
		})
	}

	if images == nil {
		images = []map[string]string{}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]any{
		"count":  len(images),
		"images": images,
	})
}
