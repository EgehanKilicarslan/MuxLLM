# =============================================================================
#  MUXLLM PROJECT MAKEFILE
# =============================================================================

# -----------------------------------------------------------------------------
#  1. CONFIGURATION & VARIABLES
# -----------------------------------------------------------------------------

# Service Directories
GATEWAY_DIR := backend-gateway
ROUTER_DIR  := backend-router
VECTOR_DIR  := backend-vector
PROTO_DIR   := proto

# Output Directories
PROTO_GEN_DIR := pb
REPORT_DIR    := reports

# Go Environment
GOBIN := $(shell go env GOPATH)/bin

# UI Colors
BOLD   := \033[1m
RESET  := \033[0m
GREEN  := \033[32m
BLUE   := \033[34m
YELLOW := \033[33m
CYAN   := \033[36m

# -----------------------------------------------------------------------------
#  2. HELP
# -----------------------------------------------------------------------------
.PHONY: help
help: ## Show this help message
	@printf "\n$(BOLD)MuxLLM - Management Console$(RESET)\n"
	@printf "Usage: $(CYAN)make [command]$(RESET)\n\n"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "$(GREEN)%-20s$(RESET) %s\n", $$1, $$2}'
	@printf "\n"

# -----------------------------------------------------------------------------
#  3. PROTOCOL BUFFERS (Code Generation)
# -----------------------------------------------------------------------------
.PHONY: gen-proto
gen-proto: ## Generate Go and Python code from .proto files
	@printf "$(BLUE)➡️  Preparing directories...$(RESET)\n"
	@mkdir -p $(GATEWAY_DIR)/$(PROTO_GEN_DIR)
	@mkdir -p $(ROUTER_DIR)/$(PROTO_GEN_DIR)
	@mkdir -p $(VECTOR_DIR)/$(PROTO_GEN_DIR)
	@touch $(ROUTER_DIR)/$(PROTO_GEN_DIR)/__init__.py
	@touch $(VECTOR_DIR)/$(PROTO_GEN_DIR)/__init__.py
	
	@printf "$(BLUE)➡️  Generating Go code (Gateway)...$(RESET)\n"
	@protoc --plugin=protoc-gen-go=$(GOBIN)/protoc-gen-go \
		--plugin=protoc-gen-go-grpc=$(GOBIN)/protoc-gen-go-grpc \
		-I=$(PROTO_DIR) \
		--go_out=$(GATEWAY_DIR)/$(PROTO_GEN_DIR) --go_opt=paths=source_relative \
		--go-grpc_out=$(GATEWAY_DIR)/$(PROTO_GEN_DIR) --go-grpc_opt=paths=source_relative \
		$(PROTO_DIR)/*.proto

	@printf "$(BLUE)➡️  Generating Python code (Router & Vector)...$(RESET)\n"
	@# Router Service
	@python3 -m grpc_tools.protoc \
		-I=$(PROTO_DIR) \
		--python_out=$(ROUTER_DIR)/$(PROTO_GEN_DIR) \
		--grpc_python_out=$(ROUTER_DIR)/$(PROTO_GEN_DIR) \
		--mypy_out=$(ROUTER_DIR)/$(PROTO_GEN_DIR) \
		--mypy_grpc_out=$(ROUTER_DIR)/$(PROTO_GEN_DIR) \
		$(PROTO_DIR)/*.proto
	@# Vector Service
	@python3 -m grpc_tools.protoc \
		-I=$(PROTO_DIR) \
		--python_out=$(VECTOR_DIR)/$(PROTO_GEN_DIR) \
		--grpc_python_out=$(VECTOR_DIR)/$(PROTO_GEN_DIR) \
		--mypy_out=$(VECTOR_DIR)/$(PROTO_GEN_DIR) \
		--mypy_grpc_out=$(VECTOR_DIR)/$(PROTO_GEN_DIR) \
		$(PROTO_DIR)/*.proto

	@printf "$(YELLOW)🔧 Patching Python imports...$(RESET)\n"
	@find $(ROUTER_DIR)/$(PROTO_GEN_DIR) -name "*_grpc.py" -exec sed -i 's/import \([a-zA-Z0-9_]*_pb2\)/from . import \1/' {} +
	@find $(VECTOR_DIR)/$(PROTO_GEN_DIR) -name "*_grpc.py" -exec sed -i 's/import \([a-zA-Z0-9_]*_pb2\)/from . import \1/' {} +
	
	@printf "$(GREEN)✅ Proto generation completed!$(RESET)\n"

# -----------------------------------------------------------------------------
#  4. DEPENDENCIES
# -----------------------------------------------------------------------------
.PHONY: deps
deps: deps-gateway deps-router deps-vector ## Install/Update all dependencies
	@printf "$(GREEN)✅ All dependencies are ready.$(RESET)\n"

.PHONY: deps-gateway
deps-gateway: ## Install Gateway (Go) dependencies
	@printf "$(BLUE)📦 [Gateway] Downloading Go modules...$(RESET)\n"
	@cd $(GATEWAY_DIR) && go mod tidy && go mod download

.PHONY: deps-router
deps-router: ## Install Router (Python) dependencies
	@printf "$(BLUE)📦 [Router] Syncing Python packages...$(RESET)\n"
	@cd $(ROUTER_DIR) && uv sync --locked --all-extras --dev

.PHONY: deps-vector
deps-vector: ## Install Vector (Python) dependencies
	@printf "$(BLUE)📦 [Vector] Syncing Python packages...$(RESET)\n"
	@cd $(VECTOR_DIR) && uv sync --locked --all-extras --dev

# -----------------------------------------------------------------------------
#  5. TESTING
# -----------------------------------------------------------------------------
.PHONY: test
test: test-gateway test-router test-vector ## Run tests for all services
	@printf "$(GREEN)✅ All tests passed successfully!$(RESET)\n"

.PHONY: test-gateway
test-gateway: ## Run Gateway tests
	@printf "$(BLUE)🐹 [Gateway] Running Go tests...$(RESET)\n"
	@mkdir -p $(GATEWAY_DIR)/$(REPORT_DIR)
	@cd $(GATEWAY_DIR) && go test ./... -v -count=1 -coverpkg=./... -coverprofile=$(REPORT_DIR)/coverage.tmp -covermode=atomic
	@cat $(GATEWAY_DIR)/$(REPORT_DIR)/coverage.tmp | grep -v "/pb/" | grep -v "/cmd/" | grep -v "/testutil" > $(GATEWAY_DIR)/$(REPORT_DIR)/coverage.txt
	@rm $(GATEWAY_DIR)/$(REPORT_DIR)/coverage.tmp

.PHONY: test-router
test-router: ## Run Router tests
	@printf "$(BLUE)🐍 [Router] Running Pytest...$(RESET)\n"
	@mkdir -p $(ROUTER_DIR)/$(REPORT_DIR)
	@cd $(ROUTER_DIR) && uv run pytest -v --cov=app --cov-report=xml:$(REPORT_DIR)/coverage.xml

.PHONY: test-vector
test-vector: ## Run Vector tests
	@printf "$(BLUE)🐍 [Vector] Running Pytest...$(RESET)\n"
	@mkdir -p $(VECTOR_DIR)/$(REPORT_DIR)
	@cd $(VECTOR_DIR) && uv run pytest -v --cov=app --cov-report=xml:$(REPORT_DIR)/coverage.xml

# -----------------------------------------------------------------------------
#  6. DOCKER OPERATIONS
# -----------------------------------------------------------------------------
.PHONY: up
up: ## Start system (background)
	@printf "$(BLUE)🐳 Starting containers...$(RESET)\n"
	@docker-compose up -d --build
	@printf "$(GREEN)✅ System is running! Run 'make logs' to monitor.$(RESET)\n"

.PHONY: down
down: ## Stop system
	@printf "$(YELLOW)🛑 Stopping containers...$(RESET)\n"
	@docker-compose down

.PHONY: restart
restart: down up ## Restart system

.PHONY: logs
logs: ## Follow container logs
	@docker-compose logs -f

# -----------------------------------------------------------------------------
#  7. CLEANUP
# -----------------------------------------------------------------------------
.PHONY: clean
clean: clean-proto clean-reports ## Clean all generated files
	@printf "$(GREEN)✅ Cleanup completed.$(RESET)\n"

.PHONY: clean-proto
clean-proto:
	@printf "$(YELLOW)🧹 Cleaning generated protos...$(RESET)\n"
	@rm -rf $(GATEWAY_DIR)/$(PROTO_GEN_DIR)
	@rm -rf $(ROUTER_DIR)/$(PROTO_GEN_DIR)
	@rm -rf $(VECTOR_DIR)/$(PROTO_GEN_DIR)

.PHONY: clean-reports
clean-reports:
	@printf "$(YELLOW)🧹 Cleaning test reports...$(RESET)\n"
	@rm -rf $(GATEWAY_DIR)/$(REPORT_DIR)
	@rm -rf $(ROUTER_DIR)/$(REPORT_DIR)
	@rm -rf $(VECTOR_DIR)/$(REPORT_DIR)

# -----------------------------------------------------------------------------
#  8. DEV TOOLS
# -----------------------------------------------------------------------------
.PHONY: tools
tools: ## Install required Go tools
	@printf "$(BLUE)🛠️  Installing protobuf tools to $(GOBIN)...$(RESET)\n"
	@mkdir -p $(GOBIN)
	@env GOBIN=$(GOBIN) go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
	@env GOBIN=$(GOBIN) go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest
	@printf "$(GREEN)✅ Tools installed!$(RESET)\n"