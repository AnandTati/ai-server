import os
import time
import subprocess
import requests
import yaml
from pathlib import Path
from jinja2 import Template
from dotenv import dotenv_values

# --- PATH CONSTANTS ---
BASE_DIR = Path(__file__).parent.resolve()
CONFIG_DIR = BASE_DIR / "ollama"
OLLAMA_DATA_DIR = BASE_DIR / "data" / "ollama"
RENDERED_DIR = OLLAMA_DATA_DIR / "rendered"
MODELS_YAML = CONFIG_DIR / "models.yaml"
TEMPLATE_FILE = CONFIG_DIR / "Modelfile.tmpl"
ENV_FILE = CONFIG_DIR / "models.env"

class ConfigManager:
    """Handles loading and validating all configuration files."""
    def __init__(self):
        self.env_vars = self._load_env()
        self.models_config = self._load_yaml()
        self.template = self._load_template()

    def _load_env(self):
        if not ENV_FILE.exists():
            raise FileNotFoundError(f"Missing {ENV_FILE}")
        return dotenv_values(ENV_FILE)

    def _load_yaml(self):
        if not MODELS_YAML.exists():
            raise FileNotFoundError(f"Missing {MODELS_YAML}")
        with open(MODELS_YAML, 'r') as f:
            return yaml.safe_load(f)

    def _load_template(self):
        if not TEMPLATE_FILE.exists():
            raise FileNotFoundError(f"Missing {TEMPLATE_FILE}")
        with open(TEMPLATE_FILE, 'r') as f:
            return Template(f.read())

    def get_actual_model_name(self, env_key):
        return self.env_vars.get(env_key)

class OllamaDockerClient:
    """Handles commands sent to the Ollama container."""
    def __init__(self, container_name="ollama", api_url="http://localhost:11434"):
        self.container = container_name
        self.api_url = api_url

    def run_exec(self, args):
        """Runs a command inside the ollama container."""
        cmd = ["docker", "exec", "-i", self.container, "ollama"] + args
        subprocess.run(cmd, check=True)

    def wait_for_ready(self, timeout=60):
        """Polls the Ollama API until it responds."""
        print(f"▶ Waiting for Ollama API at {self.api_url}...")
        start_time = time.time()
        while time.time() - start_time < timeout:
            try:
                if requests.get(f"{self.api_url}/api/tags", timeout=2).status_code == 200:
                    print("✓ Ollama is online.")
                    return True
            except requests.RequestException:
                pass
            time.sleep(2)
        return False

class ModelProcessor:
    """Orchestrates the lifecycle of model rendering and registration."""
    def __init__(self, config: ConfigManager, client: OllamaDockerClient):
        self.config = config
        self.client = client

    def process_all(self):
        """Iterates through the YAML and runs the pipeline for each model."""
        for model_id, cfg in self.config.models_config.items():
            base_env_key = cfg.get('base')
            actual_model = self.config.get_actual_model_name(base_env_key)

            if not actual_model:
                print(f"⚠️ Skipping {model_id}: Env var {base_env_key} not found.")
                continue

            print(f"\n--- Initializing Model: {model_id} ---")
            self._initialize_model(model_id, actual_model, cfg)

    def _initialize_model(self, model_id, actual_base, model_cfg):
        # 1. Pull Base
        print(f"▶ Pulling {actual_base}...")
        self.client.run_exec(["pull", actual_base])

        # 2. Render Modelfile
        rendered_content = self.config.template.render(
            base=actual_base,
            temperature=model_cfg.get('temperature', 0.7),
            top_p=model_cfg.get('top_p'),
            system=model_cfg.get('system', '')
        )
        
        modelfile_name = f"Modelfile.{model_id}"
        (RENDERED_DIR / modelfile_name).write_text(rendered_content)

        # 3. Create/Register in Ollama
        # Path relative to the container's internal filesystem
        container_path = f"/root/.ollama/rendered/{modelfile_name}"
        print(f"▶ Registering alias '{model_id}'...")
        self.client.run_exec(["create", model_id, "-f", container_path])

def start_infrastructure():
    """Ensures directories exist and Docker containers are running."""
    print("▶ Preparing environment...")
    RENDERED_DIR.mkdir(parents=True, exist_ok=True)
    
    # Check for docker compose vs docker-compose
    cmd = ["docker", "compose", "up", "-d"]
    try:
        subprocess.run(cmd, check=True)
    except FileNotFoundError:
        subprocess.run(["docker-compose", "up", "-d"], check=True)

def main():
    # Stage 1: Infrastructure
    try:
        start_infrastructure()
    except subprocess.CalledProcessError as e:
        print(f"❌ Docker failed to start: {e}")
        return

    # Stage 2: Configuration
    try:
        config_mgr = ConfigManager()
        ollama_client = OllamaDockerClient()
    except Exception as e:
        print(f"❌ Configuration Error: {e}")
        return

    # Stage 3: Readiness
    if not ollama_client.wait_for_ready():
        print("❌ Error: Ollama API timed out.")
        return

    # Stage 4: Execution
    processor = ModelProcessor(config_mgr, ollama_client)
    processor.process_all()

    print("\n✅ All models are initialized and ready.")

if __name__ == "__main__":
    main()
