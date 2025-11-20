import React, { useState } from 'react';
import { Box, Text, useInput } from 'ink';

interface TextInputProps {
  label: string;
  placeholder?: string;
  defaultValue?: string;
  onSubmit: (value: string) => void;
  onCancel?: () => void;
}

export function TextInput({ label, placeholder, defaultValue = '', onSubmit, onCancel }: TextInputProps) {
  const [value, setValue] = useState(defaultValue);

  useInput((input, key) => {
    if (key.return) {
      onSubmit(value);
    } else if (key.escape) {
      onCancel?.();
    } else if (key.backspace || key.delete) {
      setValue((prev) => prev.slice(0, -1));
    } else if (!key.ctrl && !key.meta && input.length === 1) {
      setValue((prev) => prev + input);
    }
  });

  return (
    <Box flexDirection="column">
      <Box marginBottom={1}>
        <Text bold color="cyan">{label}</Text>
      </Box>

      <Box
        borderStyle="round"
        borderColor="cyan"
        paddingX={1}
        paddingY={0}
        minWidth={50}
      >
        <Text>
          {value || <Text dimColor>{placeholder || 'Type here...'}</Text>}
          <Text color="cyan">▊</Text>
        </Text>
      </Box>

      <Box marginTop={1}>
        <Text dimColor>Enter: Submit • ESC: Cancel</Text>
      </Box>
    </Box>
  );
}
