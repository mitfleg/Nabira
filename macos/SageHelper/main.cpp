#include <algorithm>
#include <array>
#include <cstdint>
#include <iostream>
#include <limits>
#include <sstream>
#include <string>
#include <vector>

#include "onnxruntime_cxx_api.h"

namespace {

std::vector<int64_t> parse_ids(const std::string& line) {
    std::vector<int64_t> result;
    std::stringstream input(line);
    std::string item;
    while (std::getline(input, item, ',')) {
        if (!item.empty()) result.push_back(std::stoll(item));
    }
    return result;
}

void print_ids(const std::vector<int64_t>& ids) {
    for (std::size_t index = 0; index < ids.size(); ++index) {
        if (index) std::cout << ',';
        std::cout << ids[index];
    }
    std::cout << '\n' << std::flush;
}

}  // namespace

int main(int argc, char** argv) {
    if (argc != 3) {
        std::cerr << "usage: NabiraSageHelper <encoder.onnx> <decoder.onnx>\n";
        return 64;
    }

    try {
        Ort::Env env(ORT_LOGGING_LEVEL_WARNING, "nabira-sage");
        Ort::SessionOptions options;
        options.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);
        options.SetInterOpNumThreads(1);
        options.SetIntraOpNumThreads(4);
        Ort::Session encoder(env, argv[1], options);
        Ort::Session decoder(env, argv[2], options);
        Ort::MemoryInfo memory = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);

        std::string line;
        while (std::getline(std::cin, line)) {
            try {
                std::vector<int64_t> input_ids = parse_ids(line);
                if (input_ids.empty() || input_ids.size() > 220) {
                    std::cout << "ERR:input-size\n" << std::flush;
                    continue;
                }
                std::vector<int64_t> attention(input_ids.size(), 1);
                std::array<int64_t, 2> input_shape{1, static_cast<int64_t>(input_ids.size())};
                std::array<Ort::Value, 2> encoder_inputs{
                    Ort::Value::CreateTensor<int64_t>(memory, input_ids.data(), input_ids.size(), input_shape.data(), input_shape.size()),
                    Ort::Value::CreateTensor<int64_t>(memory, attention.data(), attention.size(), input_shape.data(), input_shape.size()),
                };
                const char* encoder_input_names[] = {"input_ids", "attention_mask"};
                const char* encoder_output_names[] = {"last_hidden_state"};
                auto encoder_outputs = encoder.Run(Ort::RunOptions{nullptr}, encoder_input_names,
                    encoder_inputs.data(), encoder_inputs.size(), encoder_output_names, 1);

                auto hidden_info = encoder_outputs[0].GetTensorTypeAndShapeInfo();
                std::vector<int64_t> hidden_shape = hidden_info.GetShape();
                std::size_t hidden_count = hidden_info.GetElementCount();
                auto* hidden_data = encoder_outputs[0].GetTensorMutableData<Ort::Float16_t>();

                std::vector<int64_t> generated{0};  // T5 decoder start/pad token
                const std::size_t max_tokens = std::min<std::size_t>(280, input_ids.size() * 3 + 24);
                for (std::size_t step = 0; step < max_tokens; ++step) {
                    std::array<int64_t, 2> decoder_shape{1, static_cast<int64_t>(generated.size())};
                    std::array<Ort::Value, 3> decoder_inputs{
                        Ort::Value::CreateTensor<int64_t>(memory, attention.data(), attention.size(), input_shape.data(), input_shape.size()),
                        Ort::Value::CreateTensor<int64_t>(memory, generated.data(), generated.size(), decoder_shape.data(), decoder_shape.size()),
                        Ort::Value::CreateTensor<Ort::Float16_t>(memory, hidden_data, hidden_count, hidden_shape.data(), hidden_shape.size()),
                    };
                    const char* decoder_input_names[] = {
                        "encoder_attention_mask", "input_ids", "encoder_hidden_states"
                    };
                    const char* decoder_output_names[] = {"logits"};
                    auto decoder_outputs = decoder.Run(Ort::RunOptions{nullptr}, decoder_input_names,
                        decoder_inputs.data(), decoder_inputs.size(), decoder_output_names, 1);
                    auto logits_info = decoder_outputs[0].GetTensorTypeAndShapeInfo();
                    std::vector<int64_t> logits_shape = logits_info.GetShape();
                    if (logits_shape.size() != 3 || logits_shape[2] <= 0) throw std::runtime_error("bad-logits-shape");
                    const std::size_t vocab = static_cast<std::size_t>(logits_shape[2]);
                    const std::size_t offset = (generated.size() - 1) * vocab;
                    const auto* logits = decoder_outputs[0].GetTensorData<Ort::Float16_t>();
                    float best_score = -std::numeric_limits<float>::infinity();
                    int64_t best_id = 0;
                    for (std::size_t token = 0; token < vocab; ++token) {
                        float score = logits[offset + token].ToFloat();
                        if (score > best_score) {
                            best_score = score;
                            best_id = static_cast<int64_t>(token);
                        }
                    }
                    if (best_id == 2) break;  // EOS
                    generated.push_back(best_id);
                }
                generated.erase(generated.begin());
                print_ids(generated);
            } catch (const std::exception& error) {
                std::cerr << "request failed: " << error.what() << '\n';
                std::cout << "ERR:inference\n" << std::flush;
            }
        }
    } catch (const std::exception& error) {
        std::cerr << "startup failed: " << error.what() << '\n';
        return 70;
    }
    return 0;
}
