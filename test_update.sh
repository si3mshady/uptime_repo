global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'webserver'
    static_configs:
      - targets: ['localhost:80']
  - job_name: 'custom_app'
    static_configs:
      - targets: ['localhost:8080']  # Replace with the appropriate address and port of your /health endpoint