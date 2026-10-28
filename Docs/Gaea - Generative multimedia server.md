Gaea - Generative multimedia server

Summary:
Gaea is a MSE compliant  server that processes api/mcp requests using a queue and the MLX Engine to mangage memory and model swapping.  Based on the existing pixel-agency-image-engine it extends it's generative image catalog  to enable both audio and video models.  

Our existing model mlx-engine packages get extended to enable Gaea to discover the models capabilities (audio, image, video) and supported configuration tiers.  Each model get's extended to include a UI for Gaea that handles the default configuration as well as options for processing LoRA or other cabability not in the base model.  Each model is responsible for providing a schema and db interaction for  SQLite that is stored with the Quanos main configuration db.  

Models should be able to be added to Gaea via it's GitHub repo.  Gaea should provide a way to check for newer versions of the Quanos integration provided by the model.  This should act similar to a plugin system and may require the development of a suitable plugin for models as part of this process.

Gaea provides top level api style endpoints i.e. create, edit, modify, etc... and be able to accept at json or similar dictionary that can be passed to the plugin for model specific requests (LoRA).  This keeps Gaea focused on the queue and memory management rather than the generative process which is performed by the Quaranos model connector.

Gaea UI:
Gaea should be a menu bar app with simple stop/start server and an item to open the primary UI which allows for the addition and configuration of integrated models and a dashboard for system resources and machine capability (Salvaged from the image engine)

Approach:
This is a fairly significant effort so we will plan on focusing on building the capablities in order of 1. Image, 2. Audio, 3. Video.   As part of the development we will be building in SPM's that provide a way for our other applications to  communicate with Gaea and will provide for debug and testing during development. 

During the SPM development we will also create the reference app that is simplified to focus on the development and testing of the end to end pipeline App -> SPM -> Gaea -> Model -> LoRA.  