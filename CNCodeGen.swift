//
//  main.swift
//  CodeGen
//
//  Created by Pruthvesh on 1/8/24.
//

import ApolloCodegenLib
import ArgumentParser
import CodegenCLI
import Foundation

enum CodeGenConstant {
    public static let nameSpace: String = "CNGraphQLGen"
}

enum FetchError: Error {
    case fileNotFound
    case invalidInput
    case networkError(message: String)
}

struct FetchSchema: AsyncParsableCommand {
    @Option(name: .shortAndLong, help: "Output directory")
    var outputDirectory: String = "./"

    @Option(name: .shortAndLong, help: "Input directory")
    var inputDirectory: String = "./"

    @Option(name: .shortAndLong, help: "code directory")
    var codeDirectory: String = "./"

    static var configuration = CommandConfiguration(
        commandName: "fetchSchema",
        abstract: "A brief description of your command"
    )

    private func fetchSchema(
        configuration codegenConfiguration: ApolloSchemaDownloadConfiguration,
        schemaDownloadProvider: ApolloSchemaDownloader.Type
    ) async throws {
        try await schemaDownloadProvider.fetch(
            configuration: codegenConfiguration,
            withRootURL: rootOutputURL(for: outputDirectory)
        )
    }

    func rootOutputURL(for path: String) -> URL? {
        let rootURL = URL(fileURLWithPath: path)
        if rootURL.path == FileManager.default.currentDirectoryPath {
            return nil
        }
        return rootURL
    }

    func run() async throws {
        guard let url = URL(string: "https://ganymede.castingnetworks.io/api-gw/graphql") else {
            throw FetchError.networkError(message: "Bad Schema URL")
        }

        let subject = ApolloSchemaDownloadConfiguration(
            using: .introspection(
                endpointURL: url,
                httpMethod: .POST,
                outputFormat: .SDL
            ),
            timeout: 120,
            headers: [
                .init(key: "Accept-Encoding", value: "gzip")
            ],
            outputPath: "ServerSchemaCNI.graphqls"
        )

        let jsonSubject = ApolloSchemaDownloadConfiguration(
            using: .introspection(
                endpointURL: url,
                httpMethod: .POST,
                outputFormat: .JSON
            ),
            timeout: 120,
            headers: [
                .init(key: "Accept-Encoding", value: "gzip")
            ],
            outputPath: "cni.json"
        )

        let schemaPath = "\(outputDirectory)/*.graphqls"
        let operationPath = "\(inputDirectory)/*.graphql"
        let fileInput = ApolloCodegenConfiguration.FileInput(schemaPath: schemaPath, operationSearchPaths: [operationPath])

        let schemaFileOutput = ApolloCodegenConfiguration.SchemaTypesFileOutput(path: codeDirectory, moduleType: .other)
        let fileOutput = ApolloCodegenConfiguration.FileOutput(schemaTypes: schemaFileOutput)

        var options = ApolloCodegenConfiguration.OutputOptions(
            additionalInflectionRules: [],
            selectionSetInitializers: [.all],
            pruneGeneratedFiles: true
        )

        let config = ApolloCodegenConfiguration(schemaNamespace: CodeGenConstant.nameSpace, input: fileInput, output: fileOutput, options: options)

        try await fetchSchema(configuration: subject, schemaDownloadProvider: ApolloSchemaDownloader.self)
        try await fetchSchema(configuration: jsonSubject, schemaDownloadProvider: ApolloSchemaDownloader.self)
        try await generate(configuration: config, codegenProvider: ApolloCodegen.self)
    }

    private func generate(
        configuration: ApolloCodegenConfiguration,
        codegenProvider: ApolloCodegen.Type
    ) async throws {
        var itemsToGenerate: ApolloCodegen.ItemsToGenerate = .code
        if let operationManifest = configuration.operationManifest,
           operationManifest.generateManifestOnCodeGeneration
        {
            itemsToGenerate.insert(.operationManifest)
        }

        try await codegenProvider.build(
            with: configuration,
            withRootURL: rootOutputURL(for: outputDirectory),
            itemsToGenerate: itemsToGenerate
        )
    }
}

@main
struct SMUCodeGen: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "cn_code_gen",
        abstract: "A command line utility for Apollo iOS code generation.",
        version: CodegenCLI.Constants.CLIVersion,
        subcommands: [
            FetchSchema.self
        ]
    )
}
