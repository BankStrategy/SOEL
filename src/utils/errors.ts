export class SoelError extends Error {
  constructor(message: string, public code: string) {
    super(message);
    this.name = 'SoelError';
  }
}

export class SemanticEncodingError extends SoelError {
  constructor(message: string, public rawResponse?: string) {
    super(message, 'SEMANTIC_ENCODING_ERROR');
    this.name = 'SemanticEncodingError';
  }
}

export class IRValidationError extends SoelError {
  constructor(message: string, public issues: string[]) {
    super(message, 'IR_VALIDATION_ERROR');
    this.name = 'IRValidationError';
  }
}

export class CodegenError extends SoelError {
  constructor(message: string) {
    super(message, 'CODEGEN_ERROR');
    this.name = 'CodegenError';
  }
}

export class GHCError extends SoelError {
  constructor(
    message: string,
    public stderr: string,
    public exitCode: number | null
  ) {
    super(message, 'GHC_ERROR');
    this.name = 'GHCError';
  }
}

export class OpenRouterError extends SoelError {
  constructor(message: string, public status?: number, public body?: string) {
    super(message, 'OPENROUTER_ERROR');
    this.name = 'OpenRouterError';
  }
}

export class ConfigError extends SoelError {
  constructor(message: string) {
    super(message, 'CONFIG_ERROR');
    this.name = 'ConfigError';
  }
}

export class SemanticAmbiguityError extends SoelError {
  constructor(
    message: string,
    public diagnostics: string
  ) {
    super(message, 'SEMANTIC_AMBIGUITY');
    this.name = 'SemanticAmbiguityError';
  }
}
