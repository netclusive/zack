import ZackCore

/// The Whisper files Zack was measured with: one commit per Hugging Face repository and size and SHA-256 of every
/// file. Checked file by file against the installed copy of the 2026-11-14 probe on 2026-11-15.
public enum WhisperModelManifest {
    public typealias File = ModelManifest.File

    /// WhisperKit's name of the Core ML variant: Whisper large-v3 turbo, converted by Argmax.
    public static let variant = "large-v3-v20240930_turbo_632MB"
    public static let modelRepo = "argmaxinc/whisperkit-coreml"
    public static let modelRevision = "0f63a7800b00dd0226abd051b906c246e1907482"
    /// WhisperKit's tokenizer repository for large-v3 variants (`ModelUtilities.tokenizerNameForVariant`).
    public static let tokenizerRepo = "openai/whisper-large-v3"
    public static let tokenizerRevision = "06f233fe06e710322aca913c1bc4249a0d71fce1"

    /// Every file of the variant folder, relative to it.
    public static let model: [File] = [
        File(
            path: "AudioEncoder.mlmodelc/analytics/coremldata.bin", size: 243,
            sha256: "0dd9f529c744ed3c6be67f699588f7aadc4f366b5b7301dc31bd3f199944fbcc"),
        File(
            path: "AudioEncoder.mlmodelc/coremldata.bin", size: 348,
            sha256: "ffa9eb76e8e9d9be75a4d527e5249e61d67fd43081c5aa110fd24efa6c8c5ea3"),
        File(
            path: "AudioEncoder.mlmodelc/metadata.json", size: 1974,
            sha256: "2cd0538f90a012de3f07d38669026d527490eff1dcfd2479a81c48206a90f0a2"),
        File(
            path: "AudioEncoder.mlmodelc/model.mil", size: 7_589_739,
            sha256: "ef5a252831e61bb91d6547fe1add3d0658895b518d47d70004322b40a2192668"),
        File(
            path: "AudioEncoder.mlmodelc/weights/weight.bin", size: 421_968_768,
            sha256: "e4740fa28ed65907af754af893dfce98473fafb84dd8d718ad346985fe7678c1"),
        File(
            path: "MelSpectrogram.mlmodelc/analytics/coremldata.bin", size: 243,
            sha256: "c5be419f8622083ac7046306400643539f0e7577c843448c36defc090d41e7ce"),
        File(
            path: "MelSpectrogram.mlmodelc/coremldata.bin", size: 329,
            sha256: "98efa1e351b759e078c4044668926d32bee886caf7596ae897e08e21da45565a"),
        File(
            path: "MelSpectrogram.mlmodelc/metadata.json", size: 1850,
            sha256: "2bc552e09a6f124d9e6c178dd1a6979e010206acb26308b2224887c9dcbeb35f"),
        File(
            path: "MelSpectrogram.mlmodelc/model.mil", size: 10143,
            sha256: "c270b95b5f81d7f7d0b8a3e8f991d4e5812a37cad29349868a35b91f3a6a4463"),
        File(
            path: "MelSpectrogram.mlmodelc/weights/weight.bin", size: 373_376,
            sha256: "009d9fb8f6b589accfa08cebf1c712ef07c3405229ce3cfb3a57ee033c9d8a49"),
        File(
            path: "TextDecoder.mlmodelc/analytics/coremldata.bin", size: 243,
            sha256: "4b5119bdc621c3c494f63846dc3ed43852e88826fc3b6345d42272d4b7e67724"),
        File(
            path: "TextDecoder.mlmodelc/coremldata.bin", size: 633,
            sha256: "605dad4099a82cf2c7afe93e6d8e322f1c16d4160ab27bd017ec2517b81c1bdd"),
        File(
            path: "TextDecoder.mlmodelc/metadata.json", size: 4924,
            sha256: "e3ce6d83884552ffcc2c34799e8e1211dcda59f1aaea5a79bf988c6cd16abbf0"),
        File(
            path: "TextDecoder.mlmodelc/model.mil", size: 217_177,
            sha256: "ebaf8566f367b6465276c3ed57bb99063888fa955b67828585bf19db24c85f56"),
        File(
            path: "TextDecoder.mlmodelc/weights/weight.bin", size: 203_199_860,
            sha256: "d69700903d518ada33170ab77faaaf464496fb9ff65752c6d5a6109aa2fb02db"),
        File(
            path: "TextDecoderContextPrefill.mlmodelc/analytics/coremldata.bin", size: 243,
            sha256: "97639d36c7b137ea51c3c39b175911788f4d4a601ab03cd67a4b14164c3145e1"),
        File(
            path: "TextDecoderContextPrefill.mlmodelc/coremldata.bin", size: 380,
            sha256: "2c159f5c862ec187092ea58e755d8c0b298952e22f3d75da023d7693c1c7389e"),
        File(
            path: "TextDecoderContextPrefill.mlmodelc/metadata.json", size: 2240,
            sha256: "eb88dc350fa6748a8bc3fa5fb10958152c138752ebbbac1824d2f99b4c9fc068"),
        File(
            path: "TextDecoderContextPrefill.mlmodelc/model.mil", size: 4092,
            sha256: "990ff5052fd817e28ba7c34d9d06d324c69c7c0630b6eaac9cfdf08329dbcb34"),
        File(
            path: "TextDecoderContextPrefill.mlmodelc/weights/weight.bin", size: 12_288_192,
            sha256: "1310070082639173e9d81508c5f220692d489e85655aa6883cc1c7506da7fcfd"),
        File(
            path: "config.json", size: 1149,
            sha256: "f01d83dd891791d6f12421c05d3ed8ebbe70866f10d6c9a7a7e80b558ce5a0f1"),
        File(
            path: "generation_config.json", size: 2767,
            sha256: "7fbb053a023be11fbeccd8421811610308143daa93d9617c52aab4a0fa1491c6"),
    ]

    /// The files WhisperKit's local tokenizer load reads (`tokenizer.json` and `tokenizer_config.json` required,
    /// `config.json` if present), relative to the tokenizer folder.
    public static let tokenizer: [File] = [
        File(
            path: "config.json", size: 1272,
            sha256: "ad0e8d1e46f4d01f7861a21509e5d0f977d6cc1f367a370603c92541d819807b"),
        File(
            path: "tokenizer.json", size: 2_480_617,
            sha256: "6d8cbd7cd0d8d5815e478dac67b85a26bbe77c1f5e0c6d76d1ce2abc0e5f21ca"),
        File(
            path: "tokenizer_config.json", size: 282_843,
            sha256: "844b642c73a91359722f47b35705f7174686df33d252695d8572cf9ac03a6389"),
    ]
}
