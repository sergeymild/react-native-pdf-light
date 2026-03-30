import React from 'react';
import Svg, { Path } from 'react-native-svg';

type IconProps = {
  size?: number;
  color?: string;
};

export function IcClose({ size = 20, color = 'white' }: IconProps) {
  return (
    <Svg width={size} height={size} viewBox="0 0 20 20" fill="none">
      <Path
        d="M8.62945 10L3.50003 15.1294L4.87057 16.5L9.99999 11.3706L15.1294 16.5L16.5 15.1295L11.3705 10L16.5 4.87054L15.1295 3.5L9.99999 8.62947L4.87054 3.50001L3.5 4.87056L8.62945 10Z"
        fill={color}
      />
    </Svg>
  );
}

export function IcUndo({ size = 20, color = '#9B989D' }: IconProps) {
  return (
    <Svg width={size} height={size} viewBox="0 0 20 20" fill="none">
      <Path
        d="M8 5H11C14.3136 5.00009 17 7.68635 17 11C17 14.3137 14.3136 16.9999 11 17H4V15H11C13.2091 14.9999 15 13.2091 15 11C15 8.79091 13.2091 7.00009 11 7H8V10L2 6L8 2V5Z"
        fill={color}
      />
    </Svg>
  );
}

export function IcRedo({ size = 20, color = '#9B989D' }: IconProps) {
  return (
    <Svg width={size} height={size} viewBox="0 0 20 20" fill="none">
      <Path
        d="M18 6L12 10V7H9C6.79094 7.00009 5 8.79091 5 11C5 13.2091 6.79094 14.9999 9 15H16V17H9C5.68637 16.9999 3 14.3137 3 11C3 7.68635 5.68636 5.00009 9 5H12V2L18 6Z"
        fill={color}
      />
    </Svg>
  );
}

export function IcDraw({ size = 20, color = '#F9F7FA' }: IconProps) {
  return (
    <Svg width={size} height={size} viewBox="0 0 20 20" fill="none">
      <Path
        d="M6 18L16 7.88429C17.1046 6.76694 17.1046 4.95536 16 3.83801C14.8954 2.72066 13.1046 2.72066 12 3.83801L2 13.9537V18H6Z"
        fill={color}
      />
      <Path d="M18 15.9766H11L9 17.9997L18 18V15.9766Z" fill={color} />
    </Svg>
  );
}

export function IcHighlight({ size = 20, color = 'white' }: IconProps) {
  return (
    <Svg width={size} height={size} viewBox="0 0 20 20" fill="none">
      <Path
        d="M5.83325 13.3333V4.16667C5.83325 3.70833 5.99645 3.31597 6.32284 2.98958C6.64922 2.66319 7.04159 2.5 7.49992 2.5C7.62492 2.5 7.74992 2.51389 7.87492 2.54167C7.99992 2.56944 8.11797 2.61111 8.22909 2.66667L13.2291 5.14583C13.5069 5.28472 13.7326 5.48958 13.9062 5.76042C14.0798 6.03125 14.1666 6.32639 14.1666 6.64583V13.3333H5.83325ZM3.33325 17.5L3.79159 16.1458C3.9027 15.7986 4.10409 15.5208 4.39575 15.3125C4.68742 15.1042 5.01381 15 5.37492 15H14.6249C14.986 15 15.3124 15.1042 15.6041 15.3125C15.8958 15.5208 16.0971 15.7986 16.2083 16.1458L16.6666 17.5H3.33325Z"
        fill={color}
      />
    </Svg>
  );
}

export function IcText({ size = 20, color = '#F9F7FA' }: IconProps) {
  return (
    <Svg width={size} height={size} viewBox="0 0 20 20" fill="none">
      <Path
        d="M13 2C13.7692 2 14.469 2.29156 15 2.76758C15.531 2.29156 16.2308 2 17 2H18V4H17C16.4477 4 16 4.44772 16 5V15C16 15.5523 16.4477 16 17 16H18V18H17C16.2305 18 15.531 17.7077 15 17.2314C14.469 17.7077 13.7695 18 13 18H12V16H13C13.5523 16 14 15.5523 14 15V5C14 4.44772 13.5523 4 13 4H12V2H13Z"
        fill={color}
      />
      <Path
        fillRule="evenodd"
        clipRule="evenodd"
        d="M12.0586 15H9.91211L9.04395 12.5732H4.94141L4.08789 15H2L5.70605 5H8.32324L12.0586 15ZM5.57324 10.7939H8.41211L6.98535 6.7793L5.57324 10.7939Z"
        fill={color}
      />
    </Svg>
  );
}

export function IcErase({ size = 20, color = 'white' }: IconProps) {
  return (
    <Svg width={size} height={size} viewBox="0 0 20 20" fill="none">
      <Path
        d="M14.3751 15H18.3334V16.6667H12.7084L14.3751 15ZM3.95839 16.6667L2.18756 14.8958C1.86811 14.5764 1.70492 14.1806 1.69798 13.7083C1.69103 13.2361 1.84728 12.8333 2.16673 12.5L11.3334 3C11.6528 2.66667 12.0452 2.5 12.5105 2.5C12.9758 2.5 13.3681 2.65972 13.6876 2.97917L17.8334 7.125C18.1528 7.44444 18.3126 7.84028 18.3126 8.3125C18.3126 8.78472 18.1528 9.18056 17.8334 9.5L10.8334 16.6667H3.95839Z"
        fill={color}
      />
    </Svg>
  );
}
