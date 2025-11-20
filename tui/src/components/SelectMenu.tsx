import React, { useState } from 'react';
import { Box, Text, useInput } from 'ink';

export interface MenuItem {
  label: string;
  value: string;
  description?: string;
  color?: string;
}

interface SelectMenuProps {
  items: MenuItem[];
  onSelect: (value: string) => void;
  onCancel?: () => void;
  title?: string;
  prompt?: string;
}

export function SelectMenu({ items, onSelect, onCancel, title, prompt = 'Select an option' }: SelectMenuProps) {
  const [selectedIndex, setSelectedIndex] = useState(0);

  useInput((input, key) => {
    if (key.upArrow || input === 'k') {
      setSelectedIndex((prev) => (prev > 0 ? prev - 1 : items.length - 1));
    } else if (key.downArrow || input === 'j') {
      setSelectedIndex((prev) => (prev < items.length - 1 ? prev + 1 : 0));
    } else if (key.return) {
      console.log(`[SelectMenu] Enter pressed, calling onSelect with: ${items[selectedIndex].value}`);
      onSelect(items[selectedIndex].value);
    } else if (key.escape || input === 'q' || input === '0') {
      console.log(`[SelectMenu] Cancel key pressed (${input}), calling onCancel`);
      onCancel?.();
    }
  });

  return (
    <Box flexDirection="column">
      {title && (
        <Box marginBottom={1}>
          <Text bold color="cyan">{title}</Text>
        </Box>
      )}

      <Box
        flexDirection="column"
        borderStyle="round"
        borderColor="cyan"
        padding={1}
        minWidth={60}
      >
        <Box marginBottom={1}>
          <Text dimColor>{prompt}</Text>
        </Box>

        {items.map((item, index) => {
          const isSelected = index === selectedIndex;
          const itemColor = item.color || 'white';

          return (
            <Box key={item.value} marginY={0}>
              <Box width="100%">
                <Text color={isSelected ? 'cyan' : 'gray'}>
                  {isSelected ? '▶ ' : '  '}
                </Text>
                <Text
                  bold={isSelected}
                  color={isSelected ? itemColor : 'white'}
                >
                  {item.label}
                </Text>
                {item.description && (
                  <Text dimColor> - {item.description}</Text>
                )}
              </Box>
            </Box>
          );
        })}

        <Box marginTop={1} borderTop borderStyle="single" paddingTop={1}>
          <Text dimColor>↑↓ Navigate • Enter: Select • ESC/q: Cancel</Text>
        </Box>
      </Box>
    </Box>
  );
}
