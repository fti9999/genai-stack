#syntax = docker/dockerfile:1.4

# Stage 1: Get the latest version of Ollama
FROM ollama/ollama:latest AS ollama

# Stage 2: Use Babashka for Clojure scripting
FROM babashka/babashka:latest

# Copy the Ollama binary from the first stage to the current stage
# This will be used as a client and not as a server
COPY --from=ollama /bin/ollama ./bin/ollama

# Embed the Clojure script in the Dockerfile
COPY <<EOF pull_model.clj
(ns pull-model
  ;; Require necessary namespaces
  (:require [babashka.process :as process]
            [clojure.core.async :as async]))

(try
  ;; Define local variables by getting environment variables
  (let [llm (get (System/getenv) "LLM")
        url (get (System/getenv) "OLLAMA_BASE_URL")]
    ;; Check if both `llm` and `url` are set
    (if (and llm url)
      ;; If the model is not supported by Ollama, handle accordingly
      (if (#{ "gpt-4o" "gpt-4" "gpt-3.5" "claudev2"} llm)
        (println (format "Model %s is not supported by Ollama. Handling separately." llm))
        ;; If the model is supported by Ollama, proceed with pulling the model
        (do
          ;; Print a message indicating the pulling of the model
          (println (format "pulling ollama model %s using %s" llm url))
          
          ;; Create a channel to signal completion
          (let [done (async/chan)]
            ;; Start an asynchronous loop to print progress messages
            (async/go-loop [n 0]
              ;; Wait for either the done signal or a timeout of 5000ms (5 seconds)
              (let [[v _] (async/alts! [done (async/timeout 5000)])]
                (if (= :stop v)
                  ;; If the done signal is received, exit the loop
                  :stopped
                  ;; Otherwise, print a progress message and recur with incremented count
                  (do
                    (println (format "... pulling model (%ss) - will take several minutes" (* n 10)))
                    (recur (inc n))))))
            
            ;; Run the shell command to pull the model, using the Ollama host URL
            (process/shell {:env {"OLLAMA_HOST" url} :out :inherit :err :inherit}
                           (format "bash -c './bin/ollama show %s --modelfile > /dev/null || ./bin/ollama pull %s'" llm llm))
            (async/>!! done :stop))
          
          ;; Print a message indicating the condition for pulling the model
          (println "OLLAMA model only pulled if both LLM and OLLAMA_BASE_URL are set and the LLM model is not in unsupported models")))))
  ;; Catch any throwable error and exit with status code 1
  (catch Throwable _ (System/exit 1)))
EOF

# Set the entrypoint to run the Babashka script
ENTRYPOINT ["bb", "-f", "pull_model.clj"]
