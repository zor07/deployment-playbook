#!/usr/bin/env bash
set -e

echo "Pulling latest images..."
docker compose pull

echo "Restarting services..."
docker compose up -d

echo "Cleaning up old images..."
docker image prune -f

echo "Deploy finished successfully."
